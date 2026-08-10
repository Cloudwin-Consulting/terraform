locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  # Unlike the other application stacks, nothing here is derived from
  # an upstream workload name: this stack looks nothing up, so there
  # are no hub, application spoke or monitoring spoke names to rebuild.
  resource_group_name = "rg-${local.name_suffix}"

  vnet_name            = "vnet-${local.name_suffix}"
  workspace_name       = "log-${local.name_suffix}"
  key_vault_name       = coalesce(var.key_vault_name, "kv-${local.name_suffix}")
  storage_account_name = coalesce(var.storage_account_name, replace("st${local.name_suffix}", "-", ""))
  web_app_name         = coalesce(var.web_app_name, "app-${local.name_suffix}")

  subnet_ids = module.vnet.subnet_ids

  private_endpoint_subnet_prefixes = var.subnets[var.private_endpoint_subnet_name].address_prefixes

  # Both machine roles and every SQL server carry an index, even when
  # only one of them is deployed. The whole point of this stack is that
  # each environment runs a different number of each, so scaling an
  # environment out has to add machines rather than rename - and
  # therefore replace - the ones already running.
  linux_virtual_machine_names = [
    for index in range(var.linux_virtual_machine_count) :
    "vm-${local.name_suffix}-${var.linux_virtual_machine_role}-${index}"
  ]

  windows_virtual_machine_names = [
    for index in range(var.windows_virtual_machine_count) :
    "vm-${local.name_suffix}-${var.windows_virtual_machine_role}-${index}"
  ]

  # Windows computer names are limited to 15 characters, far shorter
  # than the resource names above, so they are built from their own
  # short prefix instead.
  windows_computer_names = [
    for index in range(var.windows_virtual_machine_count) :
    "${var.windows_computer_name_prefix}${index}"
  ]

  sql_server_name_prefix = coalesce(var.sql_server_name_prefix, "sql-${local.name_suffix}")

  sql_server_names = [
    for index in range(var.sql_server_count) :
    "${local.sql_server_name_prefix}-${index}"
  ]

  # ------------------------------------------------------------
  # Private DNS
  #
  # The private endpoints below need a zone per service. A hub that is
  # managed elsewhere - and invisible from here - may already own those
  # zones, or may register endpoints into them with an Azure Policy
  # deployIfNotExists assignment, so where each zone comes from is a
  # per-environment decision:
  #
  #   existing_private_dns_zone_ids  the platform's zone is used, and
  #                                  this stack writes its records into
  #                                  it (needs write access there)
  #   create_private_dns_zones       this stack owns the zone and links
  #                                  it to its own virtual network
  #   neither                        the endpoint is created without a
  #                                  zone group, leaving registration
  #                                  to the platform's policy
  #
  # A supplied zone always wins over a created one, so an environment
  # can take some zones from the platform and own the rest.
  # ------------------------------------------------------------
  private_dns_zone_names = {
    key_vault   = "privatelink.vaultcore.azure.net"
    sql         = "privatelink.database.windows.net"
    blob        = "privatelink.blob.core.windows.net"
    queue       = "privatelink.queue.core.windows.net"
    app_service = "privatelink.azurewebsites.net"
  }

  required_private_dns_zone_names = toset(concat(
    [
      local.private_dns_zone_names.key_vault,
      local.private_dns_zone_names.sql,
      local.private_dns_zone_names.blob,
    ],
    var.enable_app_service ? [local.private_dns_zone_names.app_service] : [],
    var.enable_private_monitoring ? var.monitor_private_dns_zone_names : [],
    # Backup traffic resolves the vault through the geo-specific backup
    # zone plus the blob and queue zones the backup service also uses.
    var.enable_backup ? [
      var.backup_private_endpoint_dns_zone_name,
      local.private_dns_zone_names.queue,
    ] : [],
  ))

  created_private_dns_zone_names = var.create_private_dns_zones ? setsubtract(
    local.required_private_dns_zone_names,
    keys(var.existing_private_dns_zone_ids),
  ) : toset([])

  private_dns_zone_ids = merge(
    { for name, zone in module.private_dns_zone : name => zone.id },
    var.existing_private_dns_zone_ids,
  )

  # compact() drops the zones an environment has neither supplied nor
  # asked this stack to create, which leaves the endpoint without a
  # zone group rather than with a dangling reference.
  key_vault_private_dns_zone_ids   = compact([lookup(local.private_dns_zone_ids, local.private_dns_zone_names.key_vault, "")])
  sql_private_dns_zone_ids         = compact([lookup(local.private_dns_zone_ids, local.private_dns_zone_names.sql, "")])
  blob_private_dns_zone_ids        = compact([lookup(local.private_dns_zone_ids, local.private_dns_zone_names.blob, "")])
  app_service_private_dns_zone_ids = compact([lookup(local.private_dns_zone_ids, local.private_dns_zone_names.app_service, "")])

  backup_private_dns_zone_ids = var.enable_backup ? compact([
    lookup(local.private_dns_zone_ids, var.backup_private_endpoint_dns_zone_name, ""),
    lookup(local.private_dns_zone_ids, local.private_dns_zone_names.blob, ""),
    lookup(local.private_dns_zone_ids, local.private_dns_zone_names.queue, ""),
  ]) : []

  # The Azure Monitor private link scope endpoint resolves through the
  # four monitor zones plus the blob zone the agent's configuration
  # downloads use.
  monitor_private_dns_zone_ids = compact([
    for name in concat(var.monitor_private_dns_zone_names, [local.private_dns_zone_names.blob]) :
    lookup(local.private_dns_zone_ids, name, "")
  ])

  # The Environment tag holds the standard name of the environment,
  # while var.environment keeps the short form every resource name is
  # derived from - so the tag standard renames nothing.
  standard_environment_tags = {
    rd   = "RD"
    dev  = "Development"
    qa   = "QA"
    prod = "Production"
  }

  # The optional tags only join the set once they have a value, so no
  # resource carries an empty ExpiryDate, BusinessUnit or Repository.
  optional_tags = merge(
    var.expiry_date != null ? { ExpiryDate = var.expiry_date } : {},
    var.business_unit != null ? { BusinessUnit = var.business_unit } : {},
    var.repository != null ? { Repository = var.repository } : {},
  )

  # The tag set every resource in this stack carries: set on the
  # resources declared here and passed to every shared module, so
  # each resource is tagged in its own right rather than relying on
  # resource group tag inheritance. var.tags is merged last, so a
  # deployment can add to - or override - the standard values.
  common_tags = merge(
    {
      Application        = coalesce(var.application, var.deployment_name)
      Environment        = coalesce(var.environment_tag, lookup(local.standard_environment_tags, lower(var.environment), null))
      Owner              = var.owner
      CostCenter         = coalesce(var.cost_center, var.application, var.deployment_name)
      ManagedBy          = "Terraform"
      Criticality        = var.criticality
      Service            = var.service
      DataClassification = var.data_classification
      Lifecycle          = var.lifecycle_stage
    },
    local.optional_tags,
    var.tags,
  )
}

# ------------------------------------------------------------
# The application resource group
#
# One group holds the entire application - network, compute, data,
# secrets and monitoring alike - so the whole workload has a single
# lifecycle: one set of role assignments, policy assignments and
# locks, and a delete that takes everything with it. This is the
# deliberate difference from the spoke-based stacks, which split
# themselves across a core, network, DNS and secrets group so each
# layer can be handed to a different team.
# ------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.deployment_location
  tags     = local.common_tags
}

# ------------------------------------------------------------
# The application virtual network
#
# Three subnets, each with a single job: private endpoints for every
# service the application consumes, the virtual machines, and a
# delegated subnet for the App Service plan's regional virtual network
# integration. The network is not peered with anything: a hub that is
# managed elsewhere peers to it from its own side, which changes
# nothing here.
# ------------------------------------------------------------

module "vnet" {
  source = "../../shared/vnet"

  name                = local.vnet_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = var.address_space
  dns_servers         = var.dns_servers
  subnets             = var.subnets
  tags                = local.common_tags
}

# Application security groups the machines' network interfaces join, so
# the virtual machine subnet's rules follow the workload rather than
# its addresses: scaling a tier out needs no rule changes, and the two
# tiers stay separable inside one subnet.
module "asg_linux_virtual_machines" {
  source = "../../shared/application-security-group"

  name                = "asg-${local.name_suffix}-${var.linux_virtual_machine_role}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags
}

module "asg_windows_virtual_machines" {
  source = "../../shared/application-security-group"

  name                = "asg-${local.name_suffix}-${var.windows_virtual_machine_role}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags
}

# ------------------------------------------------------------
# Network security groups, one per subnet
# ------------------------------------------------------------

# Private endpoints only ever receive traffic, so allow the ports the
# application's own endpoints listen on from within the network and
# deny everything else.
module "nsg_private_endpoints" {
  source = "../../shared/nsg"

  name                = "nsg-${local.name_suffix}-pe"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags

  subnet_associations = {
    private-endpoints = local.subnet_ids[var.private_endpoint_subnet_name]
  }

  security_rules = [
    {
      name                       = "AllowHttpsInbound"
      description                = "Allow HTTPS to the key vault, storage, web app and monitoring private endpoints."
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowSqlInbound"
      description                = "Allow SQL clients to the database private endpoints."
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "1433"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "DenyAllInbound"
      description                = "Deny all other inbound traffic."
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
  ]
}

# The virtual machine subnet. Management traffic only arrives from the
# addresses named in management_source_address_prefixes - the platform's
# Azure Bastion subnet, or a management network - and is targeted at
# the tier that speaks the protocol, so the Windows machines are not
# reachable over SSH nor the Linux machines over RDP. Outbound traffic
# is limited to DNS, the private endpoints, the network and web egress.
# Everything else, in both directions, is denied. Machines must join
# their tier's application security group or the allow rules do not
# match them.
module "nsg_virtual_machines" {
  source = "../../shared/nsg"

  name                = "nsg-${local.name_suffix}-vm"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags

  subnet_associations = {
    virtual-machines = local.subnet_ids[var.virtual_machine_subnet_name]
  }

  security_rules = concat(
    length(var.management_source_address_prefixes) == 0 ? [] : [
      {
        name                                       = "AllowManagementSshInbound"
        description                                = "Allow SSH from the management network, e.g. the platform's Azure Bastion subnet."
        priority                                   = 100
        direction                                  = "Inbound"
        access                                     = "Allow"
        protocol                                   = "Tcp"
        source_port_range                          = "*"
        destination_port_range                     = "22"
        source_address_prefixes                    = var.management_source_address_prefixes
        destination_application_security_group_ids = [module.asg_linux_virtual_machines.id]
      },
      {
        name                                       = "AllowManagementRdpInbound"
        description                                = "Allow RDP from the management network, e.g. the platform's Azure Bastion subnet."
        priority                                   = 110
        direction                                  = "Inbound"
        access                                     = "Allow"
        protocol                                   = "Tcp"
        source_port_range                          = "*"
        destination_port_range                     = "3389"
        source_address_prefixes                    = var.management_source_address_prefixes
        destination_application_security_group_ids = [module.asg_windows_virtual_machines.id]
      },
    ],
    [
      {
        name                                       = "AllowWebInbound"
        description                                = "Allow HTTP and HTTPS from the network to the web tier, e.g. from the App Service integration subnet."
        priority                                   = 120
        direction                                  = "Inbound"
        access                                     = "Allow"
        protocol                                   = "Tcp"
        source_port_range                          = "*"
        destination_port_ranges                    = ["80", "443"]
        source_address_prefix                      = "VirtualNetwork"
        destination_application_security_group_ids = [module.asg_linux_virtual_machines.id]
      },
      {
        name                                       = "AllowApplicationTierInbound"
        description                                = "Allow the web tier to reach the application tier on its own ports."
        priority                                   = 130
        direction                                  = "Inbound"
        access                                     = "Allow"
        protocol                                   = "Tcp"
        source_port_range                          = "*"
        destination_port_ranges                    = var.application_tier_port_ranges
        source_application_security_group_ids      = [module.asg_linux_virtual_machines.id]
        destination_application_security_group_ids = [module.asg_windows_virtual_machines.id]
      },
      {
        name                       = "DenyAllInbound"
        description                = "Deny all other inbound traffic."
        priority                   = 4096
        direction                  = "Inbound"
        access                     = "Deny"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      },
      {
        name                                  = "AllowDnsOutbound"
        description                           = "Allow DNS from the machines to resolvers on the network, e.g. Azure DNS or the platform's DNS resolver."
        priority                              = 200
        direction                             = "Outbound"
        access                                = "Allow"
        protocol                              = "*"
        source_port_range                     = "*"
        destination_port_range                = "53"
        source_application_security_group_ids = [module.asg_linux_virtual_machines.id, module.asg_windows_virtual_machines.id]
        destination_address_prefix            = "VirtualNetwork"
      },
      {
        # The outbound half of AllowApplicationTierInbound. Both tiers
        # share this subnet, and a subnet's network security group is
        # evaluated on intra-subnet traffic too - outbound on the
        # sending machine, inbound on the receiving one - so without
        # this rule DenyAllOutbound drops the connection before the
        # inbound rule ever sees it.
        name                                       = "AllowApplicationTierOutbound"
        description                                = "Allow the web tier to reach the application tier on its own ports."
        priority                                   = 205
        direction                                  = "Outbound"
        access                                     = "Allow"
        protocol                                   = "Tcp"
        source_port_range                          = "*"
        destination_port_ranges                    = var.application_tier_port_ranges
        source_application_security_group_ids      = [module.asg_linux_virtual_machines.id]
        destination_application_security_group_ids = [module.asg_windows_virtual_machines.id]
      },
      {
        name                                  = "AllowPrivateEndpointsOutbound"
        description                           = "Allow the machines to reach this application's private endpoints: HTTPS and SQL."
        priority                              = 210
        direction                             = "Outbound"
        access                                = "Allow"
        protocol                              = "Tcp"
        source_port_range                     = "*"
        destination_port_ranges               = ["443", "1433"]
        source_application_security_group_ids = [module.asg_linux_virtual_machines.id, module.asg_windows_virtual_machines.id]
        destination_address_prefixes          = local.private_endpoint_subnet_prefixes
      },
      {
        name                                  = "AllowVnetHttpsOutbound"
        description                           = "Allow HTTPS from the machines to the rest of the network."
        priority                              = 220
        direction                             = "Outbound"
        access                                = "Allow"
        protocol                              = "Tcp"
        source_port_range                     = "*"
        destination_port_range                = "443"
        source_application_security_group_ids = [module.asg_linux_virtual_machines.id, module.asg_windows_virtual_machines.id]
        destination_address_prefix            = "VirtualNetwork"
      },
      {
        name                                  = "AllowInternetWebOutbound"
        description                           = "Allow web egress from the machines for OS packages and updates. A platform firewall inspects this when routes send egress through it."
        priority                              = 230
        direction                             = "Outbound"
        access                                = "Allow"
        protocol                              = "Tcp"
        source_port_range                     = "*"
        destination_port_ranges               = ["80", "443"]
        source_application_security_group_ids = [module.asg_linux_virtual_machines.id, module.asg_windows_virtual_machines.id]
        destination_address_prefix            = "Internet"
      },
      {
        name                                  = "AllowNtpOutbound"
        description                           = "Allow NTP time synchronisation from the machines."
        priority                              = 240
        direction                             = "Outbound"
        access                                = "Allow"
        protocol                              = "Udp"
        source_port_range                     = "*"
        destination_port_range                = "123"
        source_application_security_group_ids = [module.asg_linux_virtual_machines.id, module.asg_windows_virtual_machines.id]
        destination_address_prefix            = "Internet"
      },
      {
        name                                  = "AllowKmsOutbound"
        description                           = "Allow Windows activation traffic to the Azure KMS endpoints."
        priority                              = 250
        direction                             = "Outbound"
        access                                = "Allow"
        protocol                              = "Tcp"
        source_port_range                     = "*"
        destination_port_range                = "1688"
        source_application_security_group_ids = [module.asg_windows_virtual_machines.id]
        destination_address_prefix            = "Internet"
      },
      {
        name                       = "DenyAllOutbound"
        description                = "Deny all other outbound traffic from the virtual machine subnet."
        priority                   = 4096
        direction                  = "Outbound"
        access                     = "Deny"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      },
    ],
  )
}

# The delegated App Service subnet carries the web app's outbound
# traffic only and never receives inbound connections: inbound requests
# arrive at the app's private endpoint in the private endpoint subnet
# instead.
module "nsg_app_service" {
  source = "../../shared/nsg"

  name                = "nsg-${local.name_suffix}-appsvc"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags

  subnet_associations = {
    app-service = local.subnet_ids[var.app_service_subnet_name]
  }

  security_rules = [
    {
      name                       = "DenyAllInbound"
      description                = "The App Service integration subnet never receives inbound traffic."
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
  ]
}

# ------------------------------------------------------------
# Private DNS zones this stack owns, linked to its own network
#
# Created only for the zones the environment has not supplied through
# existing_private_dns_zone_ids, so a platform-owned zone is used where
# there is one and this stack fills the gaps.
# ------------------------------------------------------------

module "private_dns_zone" {
  source = "../../shared/private-dns-zone"

  for_each = local.created_private_dns_zone_names

  name                = each.value
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  virtual_network_links = {
    (local.vnet_name) = {
      virtual_network_id = module.vnet.id
    }
  }
}

# ------------------------------------------------------------
# Core services: Log Analytics, Application Insights, the key vault
# and the application's storage account
# ------------------------------------------------------------

module "log_analytics" {
  source = "../../shared/log-analytics"

  name                = local.workspace_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  retention_in_days   = var.log_retention_in_days
  daily_quota_gb      = var.log_daily_quota_gb
  tags                = local.common_tags

  # With the private link scope below, ingestion is private only. Where
  # an environment turns the scope off, the workspace has to accept
  # ingestion over the public endpoint or the agents have nowhere to
  # send telemetry.
  internet_ingestion_enabled = !var.enable_private_monitoring
}

module "application_insights" {
  source = "../../shared/application-insights"

  name                       = "appi-${local.name_suffix}"
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  log_analytics_workspace_id = module.log_analytics.id
  retention_in_days          = var.application_insights_retention_in_days
  internet_ingestion_enabled = !var.enable_private_monitoring
  tags                       = local.common_tags
}

# The Azure Monitor private link scope keeps agent configuration and
# telemetry inside the network. The data collection endpoint is the
# part the machines talk to, so it is linked into the scope alongside
# the workspace and the Application Insights component.
resource "azurerm_monitor_private_link_scope" "this" {
  count = var.enable_private_monitoring ? 1 : 0

  name                  = "ampls-${local.name_suffix}"
  resource_group_name   = azurerm_resource_group.this.name
  ingestion_access_mode = "PrivateOnly"
  query_access_mode     = "Open"
  tags                  = local.common_tags
}

resource "azurerm_monitor_private_link_scoped_service" "log_analytics" {
  count = var.enable_private_monitoring ? 1 : 0

  name                = "ampls-link-${local.workspace_name}"
  resource_group_name = azurerm_resource_group.this.name
  scope_name          = azurerm_monitor_private_link_scope.this[0].name
  linked_resource_id  = module.log_analytics.id
}

resource "azurerm_monitor_private_link_scoped_service" "application_insights" {
  count = var.enable_private_monitoring ? 1 : 0

  name                = "ampls-link-appi-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  scope_name          = azurerm_monitor_private_link_scope.this[0].name
  linked_resource_id  = module.application_insights.id
}

resource "azurerm_monitor_data_collection_endpoint" "this" {
  count = var.enable_private_monitoring ? 1 : 0

  name                          = "dce-${local.name_suffix}"
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  public_network_access_enabled = false
  tags                          = local.common_tags
}

resource "azurerm_monitor_private_link_scoped_service" "data_collection_endpoint" {
  count = var.enable_private_monitoring ? 1 : 0

  name                = "ampls-link-dce-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  scope_name          = azurerm_monitor_private_link_scope.this[0].name
  linked_resource_id  = azurerm_monitor_data_collection_endpoint.this[0].id
}

module "monitor_private_endpoint" {
  source = "../../shared/private-endpoint"

  count = var.enable_private_monitoring ? 1 : 0

  name                           = "pep-ampls-${local.name_suffix}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = local.subnet_ids[var.private_endpoint_subnet_name]
  private_connection_resource_id = azurerm_monitor_private_link_scope.this[0].id
  subresource_names              = ["azuremonitor"]
  private_dns_zone_ids           = local.monitor_private_dns_zone_ids
  tags                           = local.common_tags

  depends_on = [
    azurerm_monitor_private_link_scoped_service.log_analytics,
    azurerm_monitor_private_link_scoped_service.application_insights,
    azurerm_monitor_private_link_scoped_service.data_collection_endpoint,
  ]
}

# The application's key vault. Secrets are created from inside the
# network by the principals granted the Secrets Officer role - this
# stack deliberately writes no secret values, so none reach the state
# file or source control.
module "key_vault" {
  source = "../../shared/key-vault"

  name                = local.key_vault_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags

  secrets_officer_principal_ids = var.key_vault_secrets_officer_principal_ids

  # The workspace is created in this same apply, so its ID is unknown
  # at plan time and cannot decide whether the diagnostic setting
  # exists - hence the explicit flag here and on the modules below.
  log_analytics_workspace_id = module.log_analytics.id
  enable_diagnostics         = true
}

module "key_vault_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-${local.key_vault_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = local.subnet_ids[var.private_endpoint_subnet_name]
  private_connection_resource_id = module.key_vault.id
  subresource_names              = ["vault"]
  private_dns_zone_ids           = local.key_vault_private_dns_zone_ids
  tags                           = local.common_tags
}

module "storage" {
  source = "../../shared/storage-account"

  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_replication_type = var.storage_replication_type
  containers               = var.storage_containers
  tags                     = local.common_tags

  log_analytics_workspace_id = module.log_analytics.id
  enable_diagnostics         = true
}

module "storage_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-blob-${local.storage_account_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = local.subnet_ids[var.private_endpoint_subnet_name]
  private_connection_resource_id = module.storage.id
  subresource_names              = ["blob"]
  private_dns_zone_ids           = local.blob_private_dns_zone_ids
  tags                           = local.common_tags
}

# ------------------------------------------------------------
# Recovery Services vault (optional), protecting both virtual machine
# tiers with its daily backup policy
#
# The vault only accepts traffic through its private endpoint, and
# Azure only accepts that endpoint while the vault has no registered
# backup items - so the machines, which register as they deploy, wait
# for the endpoint below. A vault and the machines it protects must
# also share a subscription, which they do here by construction: this
# stack deploys everything into one.
# ------------------------------------------------------------

module "recovery_services_vault" {
  source = "../../shared/recovery-services-vault"

  count = var.enable_backup ? 1 : 0

  name                 = "rsv-${local.name_suffix}"
  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  storage_mode_type    = var.backup_storage_mode_type
  daily_retention_days = var.backup_daily_retention_days
  tags                 = local.common_tags
}

module "recovery_vault_private_endpoint" {
  source = "../../shared/private-endpoint"

  count = var.enable_backup ? 1 : 0

  name                           = "pep-rsv-${local.name_suffix}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = local.subnet_ids[var.private_endpoint_subnet_name]
  private_connection_resource_id = module.recovery_services_vault[0].id
  subresource_names              = ["AzureBackup"]
  private_dns_zone_ids           = local.backup_private_dns_zone_ids
  tags                           = local.common_tags
}

# ------------------------------------------------------------
# Web tier - Linux virtual machines
#
# The machines have no public IP addresses and are reached over the
# management network through the platform's Azure Bastion. SSH public
# keys are not secrets, so the key comes straight from the tfvars;
# password authentication is disabled outright.
# ------------------------------------------------------------

module "linux_virtual_machine" {
  source = "../../shared/virtual-machine"

  count = var.linux_virtual_machine_count

  # Recovery Services only accepts a private endpoint while the vault
  # has no registered backup items, so the machines (and their backup
  # registrations) wait for the endpoint.
  depends_on = [module.recovery_vault_private_endpoint]

  name                       = local.linux_virtual_machine_names[count.index]
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  subnet_id                  = local.subnet_ids[var.virtual_machine_subnet_name]
  size                       = var.linux_virtual_machine_size
  admin_username             = var.linux_admin_username
  admin_ssh_public_key       = var.linux_admin_ssh_public_key
  secure_boot_enabled        = var.secure_boot_enabled
  vtpm_enabled               = var.vtpm_enabled
  encryption_at_host_enabled = var.encryption_at_host_enabled
  tags                       = local.common_tags

  application_security_group_ids = [module.asg_linux_virtual_machines.id]

  # Machines are distributed round-robin across the availability zones.
  zone = length(var.availability_zones) > 0 ? var.availability_zones[count.index % length(var.availability_zones)] : null

  os_disk = var.linux_os_disk
  data_disks = [
    for disk in var.linux_data_disks : merge(disk, {
      name = "${local.linux_virtual_machine_names[count.index]}-${disk.name}"
    })
  ]

  source_image_id = var.linux_source_image_id

  backup = var.enable_backup ? {
    recovery_vault_name                = module.recovery_services_vault[0].name
    recovery_vault_resource_group_name = azurerm_resource_group.this.name
    backup_policy_id                   = module.recovery_services_vault[0].daily_backup_policy_id
  } : null

  # The workspace and endpoint are created in this same apply, so the
  # agent module is told explicitly what to create rather than
  # inferring it from IDs that are unknown at plan time.
  monitor_agent = var.enable_monitor_agent ? {
    log_analytics_workspace_id         = module.log_analytics.id
    data_collection_endpoint_id        = var.enable_private_monitoring ? azurerm_monitor_data_collection_endpoint.this[0].id : null
    create_data_collection_rule        = true
    associate_data_collection_endpoint = var.enable_private_monitoring
  } : null
}

# ------------------------------------------------------------
# Application tier - Windows Server virtual machines
#
# The admin password is never committed to source control: each
# machine gets its own password generated at deployment time, which
# lives in the state file alone (retrieve with `terraform output -json
# windows_virtual_machine_admin_passwords`, or rotate with
# `az vm user update`). That makes the state secret-bearing, which is
# why the pipelines for this stack publish no decodable plans.
# ------------------------------------------------------------

resource "random_password" "windows_admin" {
  count = var.windows_virtual_machine_count

  length      = 24
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  min_special = 1
}

module "windows_virtual_machine" {
  source = "../../shared/windows-virtual-machine"

  count = var.windows_virtual_machine_count

  # As with the Linux tier: the vault's private endpoint has to exist
  # before anything registers against the vault.
  depends_on = [module.recovery_vault_private_endpoint]

  name                       = local.windows_virtual_machine_names[count.index]
  computer_name              = local.windows_computer_names[count.index]
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  subnet_id                  = local.subnet_ids[var.virtual_machine_subnet_name]
  size                       = var.windows_virtual_machine_size
  admin_username             = var.windows_admin_username
  admin_password             = random_password.windows_admin[count.index].result
  license_type               = var.windows_license_type
  secure_boot_enabled        = var.secure_boot_enabled
  vtpm_enabled               = var.vtpm_enabled
  encryption_at_host_enabled = var.encryption_at_host_enabled
  tags                       = local.common_tags

  application_security_group_ids = [module.asg_windows_virtual_machines.id]

  zone = length(var.availability_zones) > 0 ? var.availability_zones[count.index % length(var.availability_zones)] : null

  os_disk = var.windows_os_disk
  data_disks = [
    for disk in var.windows_data_disks : merge(disk, {
      name = "${local.windows_virtual_machine_names[count.index]}-${disk.name}"
    })
  ]

  source_image_id = var.windows_source_image_id

  backup = var.enable_backup ? {
    recovery_vault_name                = module.recovery_services_vault[0].name
    recovery_vault_resource_group_name = azurerm_resource_group.this.name
    backup_policy_id                   = module.recovery_services_vault[0].daily_backup_policy_id
  } : null

  monitor_agent = var.enable_monitor_agent ? {
    log_analytics_workspace_id         = module.log_analytics.id
    data_collection_endpoint_id        = var.enable_private_monitoring ? azurerm_monitor_data_collection_endpoint.this[0].id : null
    create_data_collection_rule        = true
    associate_data_collection_endpoint = var.enable_private_monitoring
  } : null
}

# ------------------------------------------------------------
# Data tier - Azure SQL servers
#
# How many servers an environment runs is a per-environment decision,
# the same as the machine counts: a development environment puts every
# database on one server, while production separates them. Each server
# carries the same set of databases from var.sql_databases and is
# reached through its own private endpoint.
#
# Authentication is Microsoft Entra ID only: applications connect with
# their managed identities and administrators with the Entra ID group
# set as server administrator, so no credentials exist to store or
# rotate. Grant the machines and the web app access with
# CREATE USER ... FROM EXTERNAL PROVIDER from inside the network.
# ------------------------------------------------------------

module "sql_server" {
  source = "../../shared/sql-server"

  count = var.sql_server_count

  name                = local.sql_server_names[count.index]
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags

  azuread_administrator = {
    login_username = var.sql_entra_admin_login_username
    object_id      = var.sql_entra_admin_object_id
  }

  databases = var.sql_databases

  log_analytics_workspace_id = module.log_analytics.id
  enable_diagnostics         = true
}

module "sql_private_endpoint" {
  source = "../../shared/private-endpoint"

  count = var.sql_server_count

  name                           = "pep-${local.sql_server_names[count.index]}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = local.subnet_ids[var.private_endpoint_subnet_name]
  private_connection_resource_id = module.sql_server[count.index].id
  subresource_names              = ["sqlServer"]
  private_dns_zone_ids           = local.sql_private_dns_zone_ids
  tags                           = local.common_tags
}

# ------------------------------------------------------------
# Web app (optional)
#
# Deployed into the delegated App Service subnet through regional
# virtual network integration, so its outbound traffic reaches the
# machines, the databases and the private endpoints on this network.
# Inbound traffic arrives through its own private endpoint.
# ------------------------------------------------------------

module "app_service" {
  source = "../../shared/app-service"

  count = var.enable_app_service ? 1 : 0

  plan_name                 = "asp-${local.name_suffix}"
  web_app_name              = local.web_app_name
  resource_group_name       = azurerm_resource_group.this.name
  location                  = azurerm_resource_group.this.location
  sku_name                  = var.app_service_sku
  worker_count              = var.app_service_worker_count
  zone_balancing_enabled    = var.app_service_zone_balancing_enabled
  virtual_network_subnet_id = local.subnet_ids[var.app_service_subnet_name]
  health_check_path         = "/healthz"
  tags                      = local.common_tags

  application_stack = var.app_service_application_stack

  app_settings = merge(
    {
      APPLICATIONINSIGHTS_CONNECTION_STRING = module.application_insights.connection_string

      # The component rejects instrumentation key authentication (the
      # application-insights module disables local authentication), so
      # the SDK authenticates with the app's system-assigned identity,
      # which is granted Monitoring Metrics Publisher below. Without
      # both halves the component answers 403 and drops the telemetry.
      APPLICATIONINSIGHTS_AUTHENTICATION_STRING = "Authorization=AAD"

      KEY_VAULT_URI                 = module.key_vault.vault_uri
      STORAGE_ACCOUNT_BLOB_ENDPOINT = module.storage.primary_blob_endpoint
    },
    # The application's databases, addressed by their private
    # endpoints' names. Connections authenticate with the app's managed
    # identity, so the setting carries no credentials.
    {
      for index, name in local.sql_server_names :
      "SQL_SERVER_${index}_FQDN" => module.sql_server[index].fully_qualified_domain_name
    },
    var.app_service_app_settings,
  )

  log_analytics_workspace_id = module.log_analytics.id
  enable_diagnostics         = true
}

module "app_service_private_endpoint" {
  source = "../../shared/private-endpoint"

  count = var.enable_app_service ? 1 : 0

  name                           = "pep-${local.web_app_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = local.subnet_ids[var.private_endpoint_subnet_name]
  private_connection_resource_id = module.app_service[0].web_app_id
  subresource_names              = ["sites"]
  private_dns_zone_ids           = local.app_service_private_dns_zone_ids
  tags                           = local.common_tags
}

# ------------------------------------------------------------
# Data plane access, granted to the workloads' managed identities
#
# Every identity in the application reads its secrets and its blobs as
# itself, so nothing needs a connection string or an account key.
# ------------------------------------------------------------

resource "azurerm_role_assignment" "linux_virtual_machine_key_vault" {
  count = var.linux_virtual_machine_count

  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.linux_virtual_machine[count.index].principal_id
}

resource "azurerm_role_assignment" "windows_virtual_machine_key_vault" {
  count = var.windows_virtual_machine_count

  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.windows_virtual_machine[count.index].principal_id
}

resource "azurerm_role_assignment" "linux_virtual_machine_storage" {
  count = var.linux_virtual_machine_count

  scope                = module.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.linux_virtual_machine[count.index].principal_id
}

resource "azurerm_role_assignment" "windows_virtual_machine_storage" {
  count = var.windows_virtual_machine_count

  scope                = module.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.windows_virtual_machine[count.index].principal_id
}

resource "azurerm_role_assignment" "app_service_key_vault" {
  count = var.enable_app_service ? 1 : 0

  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.app_service[0].principal_id
}

resource "azurerm_role_assignment" "app_service_storage" {
  count = var.enable_app_service ? 1 : 0

  scope                = module.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.app_service[0].principal_id
}

# Lets the web app publish telemetry to the Application Insights
# component with its own identity, which is the only way in once the
# component has local authentication disabled.
resource "azurerm_role_assignment" "app_service_application_insights" {
  count = var.enable_app_service ? 1 : 0

  scope                = module.application_insights.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = module.app_service[0].principal_id
}

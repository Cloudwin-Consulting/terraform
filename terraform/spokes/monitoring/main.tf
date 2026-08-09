locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  # The upstream stacks this one looks up derive their names the
  # same way, from their own workload name and this environment.
  application_spoke_network_resource_group_name = "rg-${var.application_spoke_deployment_name}-${var.environment}-network"
  application_spoke_virtual_network_name        = "vnet-${var.application_spoke_deployment_name}-${var.environment}"
  hub_dns_resource_group_name                   = "rg-${var.hub_deployment_name}-${var.environment}-dns"
  hub_network_resource_group_name               = "rg-${var.hub_deployment_name}-${var.environment}-network"
  hub_virtual_network_name                      = "vnet-${var.hub_deployment_name}-${var.environment}"

  # The spoke splits itself across four resource groups so each layer
  # can be governed - and handed to a different team - on its own:
  # core for the platform services, network for the network fabric,
  # dns for the private DNS estate and secrets for the platform key
  # vault. Downstream stacks rebuild these names the same way.
  resource_group_name         = "rg-${local.name_suffix}"
  network_resource_group_name = "rg-${local.name_suffix}-network"
  dns_resource_group_name     = "rg-${local.name_suffix}-dns"
  secrets_resource_group_name = "rg-${local.name_suffix}-secrets"

  vnet_name            = "vnet-${local.name_suffix}"
  workspace_name       = "log-${local.name_suffix}"
  storage_account_name = coalesce(var.storage_account_name, "st${replace(local.name_suffix, "-", "")}")

  vnet_id    = var.enable_virtual_network ? module.vnet[0].id : null
  subnet_ids = var.enable_virtual_network ? module.vnet[0].subnet_ids : {}

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
# Resource groups
#
# The spoke is split four ways so each layer can be governed - and
# handed to a different team - on its own:
#
#   core     the monitoring platform: the workspace, its private link
#            scope, Application Insights and the log archive
#   network  the network fabric: the virtual network and its network
#            security group
#   dns      the private DNS zones the spoke owns. The spoke resolves
#            its own private endpoints through the hub's zones, so
#            nothing lands here until a deployment adds a zone of its
#            own - the group is still created, so the spoke's layout
#            and its governance match the other spokes'
#   secrets  the platform key vault
#
# The core, network and DNS groups are always created, whichever
# components the environment enables, so the layout - and the role and
# policy assignments scoped to it - is the same in every environment,
# and an operator knows where a component lands before it is turned
# on. The secrets group only exists alongside the vault it holds.
#
# Private endpoints live with the resource they publish rather than in
# the network group, so a service and its only entry point are never
# split apart.
# ------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.deployment_location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "network" {
  name     = local.network_resource_group_name
  location = var.deployment_location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "dns" {
  name     = local.dns_resource_group_name
  location = var.deployment_location
  tags     = local.common_tags
}

# ------------------------------------------------------------
# Monitoring spoke virtual network
#
# Only the virtual network and its network security group deploy by
# default; peering, DNS zone links, the workspace and everything
# behind it are opt-in through enable_* flags.
# ------------------------------------------------------------

module "vnet" {
  source = "../../shared/vnet"

  count = var.enable_virtual_network ? 1 : 0

  name                = local.vnet_name
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  address_space       = var.address_space
  tags                = local.common_tags

  subnets = {
    (var.private_endpoint_subnet_name) = {
      address_prefixes = [var.private_endpoint_subnet_prefix]
    }
  }
}

module "nsg_private_endpoints" {
  source = "../../shared/nsg"

  count = var.enable_virtual_network ? 1 : 0

  name                = "nsg-${local.name_suffix}-pe"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = local.common_tags

  subnet_associations = {
    private-endpoints = local.subnet_ids[var.private_endpoint_subnet_name]
  }

  security_rules = [
    {
      name                       = "AllowHttpsInbound"
      description                = "Allow HTTPS to private endpoints from the hub and spoke network."
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
    }
  ]
}

# ------------------------------------------------------------
# Peering with the hub (optional)
# ------------------------------------------------------------

data "azurerm_virtual_network" "hub" {
  provider = azurerm.hub

  count = var.enable_hub_peering ? 1 : 0

  name                = local.hub_virtual_network_name
  resource_group_name = local.hub_network_resource_group_name
}

module "hub_peering" {
  source = "../../shared/vnet-peering"

  count = var.enable_virtual_network && var.enable_hub_peering ? 1 : 0

  providers = {
    azurerm.hub = azurerm.hub
  }

  hub_virtual_network = {
    id                  = data.azurerm_virtual_network.hub[0].id
    name                = data.azurerm_virtual_network.hub[0].name
    resource_group_name = local.hub_network_resource_group_name
  }

  spoke_virtual_network = {
    id                  = module.vnet[0].id
    name                = module.vnet[0].name
    resource_group_name = azurerm_resource_group.network.name
  }

  allow_gateway_transit = var.use_hub_gateway
  use_remote_gateways   = var.use_hub_gateway
}

# ------------------------------------------------------------
# Peering with the application spoke (optional)
#
# Hub peering is not transitive: agents and applications in the
# application spoke reach this spoke's private ingestion endpoint
# through this direct peering (or through a routed path via a hub
# firewall, in which case leave this disabled).
# ------------------------------------------------------------

data "azurerm_virtual_network" "application_spoke" {
  provider = azurerm.app_spoke

  count = var.enable_application_spoke_peering ? 1 : 0

  name                = local.application_spoke_virtual_network_name
  resource_group_name = local.application_spoke_network_resource_group_name
}

# The application spoke fills the module's hub role: its side of the
# peering is created through the app_spoke provider.
module "application_spoke_peering" {
  source = "../../shared/vnet-peering"

  count = var.enable_virtual_network && var.enable_application_spoke_peering ? 1 : 0

  providers = {
    azurerm.hub = azurerm.app_spoke
  }

  hub_virtual_network = {
    id                  = data.azurerm_virtual_network.application_spoke[0].id
    name                = data.azurerm_virtual_network.application_spoke[0].name
    resource_group_name = local.application_spoke_network_resource_group_name
  }

  spoke_virtual_network = {
    id                  = module.vnet[0].id
    name                = module.vnet[0].name
    resource_group_name = azurerm_resource_group.network.name
  }
}

# Link the spoke to the hub's private DNS zones so private endpoint
# names resolve from inside the spoke (optional). The links live with
# the zones in the hub, so they are created through the hub provider.
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  provider = azurerm.hub

  for_each = var.enable_virtual_network && var.enable_hub_dns_zone_links ? toset(var.hub_private_dns_zone_names) : []

  name                  = "link-${local.vnet_name}"
  resource_group_name   = local.hub_dns_resource_group_name
  private_dns_zone_name = each.value
  virtual_network_id    = module.vnet[0].id
  registration_enabled  = false
  tags                  = local.common_tags
}

# ------------------------------------------------------------
# Log Analytics behind an Azure Monitor Private Link Scope (optional)
#
# Ingestion is private only. Diagnostic and agent traffic from the hub
# and spokes reaches the workspace through the scope's private endpoint.
# ------------------------------------------------------------

module "log_analytics" {
  source = "../../shared/log-analytics"

  count = var.enable_log_analytics ? 1 : 0

  name                = local.workspace_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  retention_in_days   = var.log_retention_in_days
  tags                = local.common_tags
}

resource "azurerm_monitor_private_link_scope" "this" {
  count = var.enable_log_analytics ? 1 : 0

  name                  = "ampls-${local.name_suffix}"
  resource_group_name   = azurerm_resource_group.this.name
  ingestion_access_mode = "PrivateOnly"
  query_access_mode     = "Open"
  tags                  = local.common_tags
}

resource "azurerm_monitor_private_link_scoped_service" "log_analytics" {
  count = var.enable_log_analytics ? 1 : 0

  name                = "ampls-link-${local.workspace_name}"
  resource_group_name = azurerm_resource_group.this.name
  scope_name          = azurerm_monitor_private_link_scope.this[0].name
  linked_resource_id  = module.log_analytics[0].id
}

# Regional data collection endpoint for the Azure Monitor Agent. With
# ingestion locked to PrivateOnly, agents need an endpoint inside the
# private link scope to fetch their data collection rule configuration
# and to deliver telemetry; VM stacks associate it alongside their
# rules.
resource "azurerm_monitor_data_collection_endpoint" "this" {
  count = var.enable_log_analytics ? 1 : 0

  name                          = "dce-${local.name_suffix}"
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  public_network_access_enabled = false
  tags                          = local.common_tags
}

resource "azurerm_monitor_private_link_scoped_service" "data_collection_endpoint" {
  count = var.enable_log_analytics ? 1 : 0

  name                = "ampls-link-dce-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  scope_name          = azurerm_monitor_private_link_scope.this[0].name
  linked_resource_id  = azurerm_monitor_data_collection_endpoint.this[0].id
}

data "azurerm_private_dns_zone" "ampls" {
  provider = azurerm.hub

  for_each = var.enable_virtual_network && var.enable_log_analytics ? toset(var.ampls_private_dns_zone_names) : []

  name                = each.value
  resource_group_name = local.hub_dns_resource_group_name
}

module "ampls_private_endpoint" {
  source = "../../shared/private-endpoint"

  count = var.enable_virtual_network && var.enable_log_analytics ? 1 : 0

  name                           = "pep-ampls-${local.name_suffix}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = local.subnet_ids[var.private_endpoint_subnet_name]
  private_connection_resource_id = azurerm_monitor_private_link_scope.this[0].id
  subresource_names              = ["azuremonitor"]
  private_dns_zone_ids           = [for zone in data.azurerm_private_dns_zone.ampls : zone.id]
  tags                           = local.common_tags

  depends_on = [azurerm_monitor_private_link_scoped_service.log_analytics]
}

# ------------------------------------------------------------
# Application Insights (optional), stored in the workspace and
# ingesting through the private link scope
# ------------------------------------------------------------

module "application_insights" {
  source = "../../shared/application-insights"

  count = var.enable_application_insights ? 1 : 0

  name                       = "appi-${local.name_suffix}"
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  log_analytics_workspace_id = module.log_analytics[0].id
  tags                       = local.common_tags
}

resource "azurerm_monitor_private_link_scoped_service" "application_insights" {
  count = var.enable_application_insights ? 1 : 0

  name                = "ampls-link-appi-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  scope_name          = azurerm_monitor_private_link_scope.this[0].name
  linked_resource_id  = module.application_insights[0].id
}

# ------------------------------------------------------------
# Storage account for long-term log archiving (optional)
#
# The workspace's data export rule continuously writes the selected
# tables into the account, creating an am-<table> container per table.
# ------------------------------------------------------------

module "log_archive_storage" {
  source = "../../shared/storage-account"

  count = var.enable_log_archive_storage ? 1 : 0

  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags

  # The archive holds long-term retention data, so it replicates
  # geo-zone-redundantly by default.
  account_replication_type = var.log_archive_replication_type

  # The account defaults to private-only access with shared key
  # authorisation disabled. Azure Monitor's data export delivers
  # through the account's public endpoint as a trusted Microsoft
  # service and authorises with shared-key access (it has no managed
  # identity), so if exported logs must keep flowing, opt the account
  # back in through these variables - the account's network rules
  # still deny everything except the trusted bypass, and readers come
  # in through the private endpoint either way.
  public_network_access_enabled = var.log_archive_public_network_access_enabled
  shared_access_key_enabled     = var.log_archive_shared_access_key_enabled

  # Optional customer-managed key encryption with a key pre-created
  # from inside the network, e.g. in the spoke's platform key vault.
  customer_managed_key = var.log_archive_customer_managed_key

  # Blob and queue request logs go to the workspace deployed above.
  # The workspace deploys in this same apply, so its ID is unknown at
  # plan time and cannot decide whether the settings exist.
  enable_diagnostics         = true
  log_analytics_workspace_id = module.log_analytics[0].id
}

# Continuously exports the selected workspace tables into the archive
# account.
resource "azurerm_log_analytics_data_export_rule" "archive" {
  count = var.enable_log_archive_storage ? 1 : 0

  name                    = "export-${local.storage_account_name}"
  resource_group_name     = azurerm_resource_group.this.name
  workspace_resource_id   = module.log_analytics[0].id
  destination_resource_id = module.log_archive_storage[0].id
  table_names             = var.log_archive_table_names
  enabled                 = true
}

data "azurerm_private_dns_zone" "blob" {
  provider = azurerm.hub

  count = var.enable_virtual_network && var.enable_log_archive_storage ? 1 : 0

  name                = "privatelink.blob.core.windows.net"
  resource_group_name = local.hub_dns_resource_group_name
}

module "storage_private_endpoint" {
  source = "../../shared/private-endpoint"

  count = var.enable_virtual_network && var.enable_log_archive_storage ? 1 : 0

  name                           = "pep-blob-${local.storage_account_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = local.subnet_ids[var.private_endpoint_subnet_name]
  private_connection_resource_id = module.log_archive_storage[0].id
  subresource_names              = ["blob"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.blob[0].id]
  tags                           = local.common_tags
}

# ------------------------------------------------------------
# Platform key vault (optional), in the secrets resource group
#
# Administrators pre-load secrets here through the Secrets Officer
# role from inside the network, ahead of the deployments that need
# them.
# ------------------------------------------------------------

resource "azurerm_resource_group" "secrets" {
  count = var.enable_platform_key_vault ? 1 : 0

  name     = local.secrets_resource_group_name
  location = var.deployment_location
  tags     = local.common_tags
}

data "azurerm_private_dns_zone" "key_vault" {
  provider = azurerm.hub

  count = var.enable_platform_key_vault ? 1 : 0

  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = local.hub_dns_resource_group_name
}

module "platform_key_vault" {
  source = "../../shared/key-vault"

  count = var.enable_platform_key_vault ? 1 : 0

  name                = coalesce(var.platform_key_vault_name, "kv-${local.name_suffix}")
  resource_group_name = azurerm_resource_group.secrets[0].name
  location            = azurerm_resource_group.secrets[0].location
  tags                = local.common_tags

  secrets_officer_principal_ids = var.platform_key_vault_secrets_officer_principal_ids

  # The workspace deploys in this same apply, so its ID is unknown at
  # plan time; the plan-time flag decides whether diagnostics exist.
  enable_diagnostics         = var.enable_log_analytics
  log_analytics_workspace_id = var.enable_log_analytics ? module.log_analytics[0].id : null
}

module "platform_key_vault_private_endpoint" {
  source = "../../shared/private-endpoint"

  count = var.enable_platform_key_vault ? 1 : 0

  name                           = "pep-${module.platform_key_vault[0].name}"
  resource_group_name            = azurerm_resource_group.secrets[0].name
  location                       = azurerm_resource_group.secrets[0].location
  subnet_id                      = local.subnet_ids[var.private_endpoint_subnet_name]
  private_connection_resource_id = module.platform_key_vault[0].id
  subresource_names              = ["vault"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.key_vault[0].id]
  tags                           = local.common_tags
}

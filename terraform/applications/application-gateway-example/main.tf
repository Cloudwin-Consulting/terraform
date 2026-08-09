locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  # The upstream stacks this one looks up derive their names the
  # same way, from their own workload name and this environment.
  log_analytics_workspace_name   = "log-${var.monitoring_deployment_name}-${var.environment}"
  monitoring_resource_group_name = "rg-${var.monitoring_deployment_name}-${var.environment}"

  resource_group_name      = "rg-${local.name_suffix}"
  virtual_network_name     = "vnet-${local.name_suffix}"
  application_gateway_name = "agw-${local.name_suffix}"

  application_gateway_subnet_prefix = var.application_gateway_subnet_prefix

  # The gateway's internal frontend. The tenth address of the subnet by
  # convention, matching how the application spoke derives its own -
  # override it when the gateway must sit on a fixed address something
  # else already names (a firewall DNAT rule, a DNS record).
  private_ip_address = coalesce(
    var.application_gateway_private_ip_address,
    cidrhost(local.application_gateway_subnet_prefix, 10)
  )

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

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.deployment_location
  tags     = local.common_tags
}

# ------------------------------------------------------------
# Existing platform resources: the monitoring workspace the gateway's
# access, performance and firewall logs are sent to.
# ------------------------------------------------------------

data "azurerm_log_analytics_workspace" "monitoring" {
  provider = azurerm.monitoring

  count = var.enable_diagnostics ? 1 : 0

  name                = local.log_analytics_workspace_name
  resource_group_name = local.monitoring_resource_group_name
}

# ------------------------------------------------------------
# Application Gateway - placeholder example
#
# A self-contained regional entry point: its own virtual network with
# the dedicated gateway subnet the v2 SKU requires, a network security
# group carrying the platform rules the SKU needs, and a gateway with
# one private listener, backend pool, health probe and routing rule.
#
# The backend pool is deliberately a dummy hostname
# (placeholder-backend.example.com): the gateway deploys complete and
# reports the backend unhealthy until the pool names something real -
# a 502 from the listener is the expected state of this example rather
# than a deployment failure.
#
# The network is standalone and unpeered, on a range outside the hub
# and spoke plan (10.250.0.0/24 by default), so the example deploys on
# its own without touching an existing topology. To adopt it in the
# spoke instead, set the spoke's enable_application_gateway - the
# application spoke deploys the same module onto its own gateway
# subnet, behind the hub firewall's DNAT rule.
# ------------------------------------------------------------

module "vnet" {
  source = "../../shared/vnet"

  name                = local.virtual_network_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = [var.address_space]
  tags                = local.common_tags

  subnets = {
    (var.application_gateway_subnet_name) = {
      address_prefixes = [local.application_gateway_subnet_prefix]
    }
  }
}

# The gateway subnet accepts gateway traffic from within the network
# plus the platform traffic the v2 SKU needs: the gateway manager
# control plane and Azure Load Balancer health probes. Without the
# first of those the gateway never reaches a healthy provisioning
# state.
module "nsg_application_gateway" {
  source = "../../shared/nsg"

  name                = "nsg-${local.name_suffix}-agw"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags

  subnet_associations = {
    app-gateway = module.vnet.subnet_ids[var.application_gateway_subnet_name]
  }

  security_rules = [
    {
      name                       = "AllowWebInbound"
      description                = "Allow HTTP and HTTPS to the gateway listeners from within the network."
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["80", "443"]
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowGatewayManagerInbound"
      description                = "Allow the gateway manager control plane to manage the v2 gateway."
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "65200-65535"
      source_address_prefix      = "GatewayManager"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowAzureLoadBalancerInbound"
      description                = "Allow Azure Load Balancer health probes to the gateway."
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "*"
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

module "application_gateway" {
  source = "../../shared/application-gateway"

  name                = local.application_gateway_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = module.vnet.subnet_ids[var.application_gateway_subnet_name]
  private_ip_address  = local.private_ip_address
  sku_name            = var.application_gateway_sku
  sku_tier            = var.application_gateway_sku
  waf_mode            = var.application_gateway_waf_mode
  min_capacity        = var.application_gateway_min_capacity
  max_capacity        = var.application_gateway_max_capacity
  zones               = var.application_gateway_zones
  tags                = local.common_tags

  # The dummy backend. Swap backend_fqdns for backend_ip_addresses when
  # the backend has no hostname of its own - a Kubernetes internal load
  # balancer frontend, for instance - and set backend_protocol to Http
  # for a backend that terminates no TLS.
  backend_fqdns          = var.backend_fqdns
  backend_ip_addresses   = var.backend_ip_addresses
  backend_protocol       = var.backend_protocol
  backend_port           = var.backend_port
  backend_host_name      = var.backend_host_name
  backend_probe_path     = var.backend_probe_path
  backend_probe_protocol = var.backend_probe_protocol

  # Terminating TLS at the listener needs a certificate in a key vault
  # and a user-assigned identity that can read it. Left null, the
  # listener is plain HTTP on port 80 - acceptable for a placeholder
  # inside a private network, and the first thing to change when this
  # example becomes a real entry point.
  ssl_certificate_key_vault_secret_id = var.ssl_certificate_key_vault_secret_id
  identity_ids                        = var.identity_ids

  log_analytics_workspace_id = var.enable_diagnostics ? data.azurerm_log_analytics_workspace.monitoring[0].id : null
}

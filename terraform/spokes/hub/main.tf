locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  # The spoke splits itself across four resource groups so each layer
  # can be governed - and handed to a different team - on its own:
  # core for the platform services, network for the network fabric,
  # dns for the private DNS estate and secrets for the platform key
  # vault. Downstream stacks rebuild these names the same way.
  resource_group_name         = "rg-${local.name_suffix}"
  network_resource_group_name = "rg-${local.name_suffix}-network"
  dns_resource_group_name     = "rg-${local.name_suffix}-dns"
  secrets_resource_group_name = "rg-${local.name_suffix}-secrets"

  vnet_name = "vnet-${local.name_suffix}"

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
# The hub is split four ways so each layer can be governed - and
# handed to a different team - on its own:
#
#   core     the platform services the hub offers the estate, e.g.
#            the Azure Monitor action group
#   network  the network fabric: the virtual network, its network
#            security groups and the gateways that connect it -
#            Bastion, the firewall and the VPN gateway
#   dns      the private DNS estate: the zones, their virtual network
#            links and the DNS private resolver that answers for them
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
# Hub virtual network
#
# Only the virtual network deploys by default; every other component
# is opt-in through an enable_* flag. GatewaySubnet and
# AzureFirewallSubnet are always reserved so the VPN gateway and Azure
# Firewall can be enabled without re-addressing the hub. The DNS
# resolver's delegated inbound subnet is only created alongside the
# resolver.
# ------------------------------------------------------------

module "vnet" {
  source = "../../shared/vnet"

  count = var.enable_virtual_network ? 1 : 0

  name                = local.vnet_name
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  address_space       = var.address_space
  tags                = local.common_tags

  subnets = merge(
    {
      "GatewaySubnet" = {
        address_prefixes = [var.gateway_subnet_prefix]
      }

      "AzureFirewallSubnet" = {
        address_prefixes = [var.firewall_subnet_prefix]
      }

      "snet-hub-shared" = {
        address_prefixes = [var.shared_subnet_prefix]
      }
    },

    var.enable_bastion && var.bastion_sku != "Developer" ? {
      "AzureBastionSubnet" = {
        address_prefixes = [var.bastion_subnet_prefix]
      }
    } : {},

    var.enable_dns_resolver ? {
      "snet-dns-resolver-inbound" = {
        address_prefixes = [var.dns_resolver_inbound_subnet_prefix]

        delegation = {
          name         = "dnsresolver"
          service_name = "Microsoft.Network/dnsResolvers"
          actions = [
            "Microsoft.Network/virtualNetworks/subnets/join/action"
          ]
        }
      }
    } : {}
  )
}

module "nsg_shared" {
  source = "../../shared/nsg"

  count = var.enable_virtual_network ? 1 : 0

  name                = "nsg-${local.name_suffix}-shared"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = local.common_tags

  subnet_associations = {
    shared = local.subnet_ids["snet-hub-shared"]
  }

  security_rules = [
    {
      name                       = "AllowBastionSshInbound"
      description                = "Allow SSH from the Azure Bastion subnet."
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = var.bastion_subnet_prefix
      destination_address_prefix = var.shared_subnet_prefix
    },
    {
      name                       = "AllowHttpsInbound"
      description                = "Allow HTTPS to private endpoints in the shared subnet from the hub and spoke network."
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = var.shared_subnet_prefix
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
# Azure Bastion (optional) - the only managed entry point into the
# network
#
# The Developer SKU attaches to the virtual network as a whole and
# must not have an IP configuration, so the public IP and the
# ip_configuration block only exist on the other SKUs, which deploy
# into AzureBastionSubnet instead.
# ------------------------------------------------------------

resource "azurerm_public_ip" "bastion" {
  count = var.enable_virtual_network && var.enable_bastion && var.bastion_sku != "Developer" ? 1 : 0

  name                = "pip-bas-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_bastion_host" "this" {
  count = var.enable_virtual_network && var.enable_bastion ? 1 : 0

  name                = "bas-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  virtual_network_id  = var.bastion_sku == "Developer" ? local.vnet_id : null
  sku                 = var.bastion_sku
  tags                = local.common_tags

  dynamic "ip_configuration" {
    for_each = var.bastion_sku == "Developer" ? [] : [1]

    content {
      name                 = "bastion-ip-configuration"
      subnet_id            = local.subnet_ids["AzureBastionSubnet"]
      public_ip_address_id = azurerm_public_ip.bastion[0].id
    }
  }
}

# ------------------------------------------------------------
# Private DNS zones for private endpoints (optional), in the DNS
# resource group
#
# The hub owns the private DNS zones. Each spoke links its virtual
# network to these zones so private endpoint names resolve everywhere.
# Required by every stack that deploys a private endpoint.
# ------------------------------------------------------------

resource "azurerm_private_dns_zone" "this" {
  for_each = var.enable_private_dns_zones ? toset(concat(var.private_dns_zone_names, var.additional_private_dns_zone_names)) : []

  name                = each.value
  resource_group_name = azurerm_resource_group.dns.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each = var.enable_virtual_network ? azurerm_private_dns_zone.this : {}

  name                  = "link-${local.vnet_name}"
  resource_group_name   = azurerm_resource_group.dns.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = local.vnet_id
  registration_enabled  = false
  tags                  = local.common_tags
}

# ------------------------------------------------------------
# Azure Firewall (optional)
#
# The policy is provisioned with the worked baseline rules from
# firewall_rule_collection_groups: outbound network rules for platform
# dependencies, outbound application rules for OS updates and source
# control, and an inbound DNAT rule publishing the application
# gateway's private frontend through the firewall's public IP. When
# egress is forced through the firewall, add route tables to the spoke
# subnets with the firewall's private IP as the next hop.
# ------------------------------------------------------------

module "firewall" {
  source = "../../shared/firewall"

  count = var.enable_virtual_network && var.enable_firewall ? 1 : 0

  name                = "afw-${local.name_suffix}"
  policy_name         = "afwp-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  subnet_id           = local.subnet_ids["AzureFirewallSubnet"]
  sku_tier            = var.firewall_sku_tier
  zones               = var.firewall_zones
  dns_proxy_enabled   = var.firewall_dns_proxy_enabled
  dns_servers         = var.firewall_dns_servers
  tags                = local.common_tags

  threat_intelligence_mode = var.firewall_threat_intelligence_mode
  idps_mode                = var.firewall_idps_mode

  rule_collection_groups = var.firewall_rule_collection_groups
}

# ------------------------------------------------------------
# Azure DNS Private Resolver (optional), in the DNS resource group
# alongside the zones it answers for
#
# Gives clients outside the network (e.g. on-premises over the VPN
# gateway) an IP address that resolves the hub's private DNS zones.
# ------------------------------------------------------------

module "dns_resolver" {
  source = "../../shared/private-dns-resolver"

  count = var.enable_virtual_network && var.enable_dns_resolver ? 1 : 0

  name                = "dnspr-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.dns.name
  location            = azurerm_resource_group.dns.location
  virtual_network_id  = local.vnet_id
  inbound_subnet_id   = local.subnet_ids["snet-dns-resolver-inbound"]
  tags                = local.common_tags
}

# ------------------------------------------------------------
# VPN gateway (optional)
#
# Connections and local network gateways are environment-specific and
# attached separately. Once deployed, enable gateway transit through
# the vnet-peering module variables so spokes can use it.
# ------------------------------------------------------------

module "vpn_gateway" {
  source = "../../shared/vpn-gateway"

  count = var.enable_virtual_network && var.enable_vpn_gateway ? 1 : 0

  name                = "vgw-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  subnet_id           = local.subnet_ids["GatewaySubnet"]
  sku                 = var.vpn_gateway_sku
  zones               = var.vpn_gateway_zones
  tags                = local.common_tags
}

# ------------------------------------------------------------
# Azure Monitor alerting (optional) - subscription service and
# resource health alerts delivered to the operations team
#
# The alerts always watch this deployment's own subscription, and there
# is no override: Azure requires an activity log alert's scope to sit in
# the same subscription as the alert rule, so an alert rule deployed
# here cannot monitor another subscription. To watch a second
# subscription, deploy this stack's alerting into it as well.
# ------------------------------------------------------------

module "monitor" {
  source = "../../shared/azure-monitor"

  count = var.enable_monitor_alerts ? 1 : 0

  name                    = "ag-${local.name_suffix}"
  resource_group_name     = azurerm_resource_group.this.name
  action_group_short_name = var.monitor_action_group_short_name
  email_receivers         = var.monitor_alert_email_receivers
  alert_scope_id          = "/subscriptions/${var.deployment_subscription_id}"
  tags                    = local.common_tags
}

# ------------------------------------------------------------
# Platform key vault (optional), in the secrets resource group
#
# Administrators pre-load secrets here through the Secrets Officer
# role from inside the network, ahead of the deployments that need
# them. The private endpoint lands in the shared services subnet, and
# names resolve through the hub's own vault DNS zone when the private
# DNS zones are enabled.
# ------------------------------------------------------------

resource "azurerm_resource_group" "secrets" {
  count = var.enable_platform_key_vault ? 1 : 0

  name     = local.secrets_resource_group_name
  location = var.deployment_location
  tags     = local.common_tags
}

module "platform_key_vault" {
  source = "../../shared/key-vault"

  count = var.enable_platform_key_vault ? 1 : 0

  name                = coalesce(var.platform_key_vault_name, "kv-${local.name_suffix}")
  resource_group_name = azurerm_resource_group.secrets[0].name
  location            = azurerm_resource_group.secrets[0].location
  tags                = local.common_tags

  secrets_officer_principal_ids = var.platform_key_vault_secrets_officer_principal_ids
}

module "platform_key_vault_private_endpoint" {
  source = "../../shared/private-endpoint"

  count = var.enable_platform_key_vault ? 1 : 0

  name                           = "pep-${module.platform_key_vault[0].name}"
  resource_group_name            = azurerm_resource_group.secrets[0].name
  location                       = azurerm_resource_group.secrets[0].location
  subnet_id                      = local.subnet_ids["snet-hub-shared"]
  private_connection_resource_id = module.platform_key_vault[0].id
  subresource_names              = ["vault"]
  private_dns_zone_ids           = [azurerm_private_dns_zone.this["privatelink.vaultcore.azure.net"].id]
  tags                           = local.common_tags
}

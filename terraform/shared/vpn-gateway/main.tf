terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A route-based VPN gateway in the hub's GatewaySubnet. Connections and
# local network gateways are environment-specific and are attached by
# the caller. Deployment takes 30 minutes or more.

resource "azurerm_public_ip" "this" {
  name                = "${var.name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  tags                = var.tags
}

# The route-based gateway in the GatewaySubnet.
resource "azurerm_virtual_network_gateway" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = var.sku
  active_active       = false
  tags                = var.tags

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.this.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = var.subnet_id
  }
}

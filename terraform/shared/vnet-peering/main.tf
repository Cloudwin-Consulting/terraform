terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = "~> 4.0"
      configuration_aliases = [azurerm.hub]
    }
  }
}

# Creates both directions of a hub and spoke peering. The spoke side is
# created through the default provider and the hub side through the
# azurerm.hub provider, so the virtual networks may live in different
# subscriptions - pass the same provider for both when they share one.
# The deployment identity needs permission over both virtual networks
# either way.

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "peer-${var.spoke_virtual_network.name}-to-${var.hub_virtual_network.name}"
  resource_group_name          = var.spoke_virtual_network.resource_group_name
  virtual_network_name         = var.spoke_virtual_network.name
  remote_virtual_network_id    = var.hub_virtual_network.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = var.allow_forwarded_traffic
  allow_gateway_transit        = false
  use_remote_gateways          = var.use_remote_gateways
}

# The hub side of the peering, optionally allowing gateway transit.
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  provider = azurerm.hub

  name                         = "peer-${var.hub_virtual_network.name}-to-${var.spoke_virtual_network.name}"
  resource_group_name          = var.hub_virtual_network.resource_group_name
  virtual_network_name         = var.hub_virtual_network.name
  remote_virtual_network_id    = var.spoke_virtual_network.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = var.allow_forwarded_traffic
  allow_gateway_transit        = var.allow_gateway_transit
  use_remote_gateways          = false
}

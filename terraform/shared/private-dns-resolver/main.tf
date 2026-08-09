terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Azure DNS Private Resolver with an inbound endpoint, so clients
# outside the virtual network (e.g. on-premises over VPN) can resolve
# the hub's private DNS zones through the endpoint's IP address.

resource "azurerm_private_dns_resolver" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  virtual_network_id  = var.virtual_network_id
  tags                = var.tags
}

# The inbound endpoint whose IP address external DNS forwarders
# target.
resource "azurerm_private_dns_resolver_inbound_endpoint" "this" {
  name                    = "${var.name}-in"
  private_dns_resolver_id = azurerm_private_dns_resolver.this.id
  location                = var.location
  tags                    = var.tags

  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = var.inbound_subnet_id
  }
}

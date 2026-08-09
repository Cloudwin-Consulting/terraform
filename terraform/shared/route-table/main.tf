terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A route table with its routes and subnet associations, e.g. to force
# spoke egress through the hub firewall's private IP address.

resource "azurerm_route_table" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  bgp_route_propagation_enabled = var.bgp_route_propagation_enabled
  tags                          = var.tags

  dynamic "route" {
    for_each = var.routes

    content {
      name                   = route.value.name
      address_prefix         = route.value.address_prefix
      next_hop_type          = route.value.next_hop_type
      next_hop_in_ip_address = route.value.next_hop_in_ip_address
    }
  }
}

# Attaches the route table to the given subnets.
resource "azurerm_subnet_route_table_association" "this" {
  for_each = var.subnet_associations

  subnet_id      = each.value
  route_table_id = azurerm_route_table.this.id
}

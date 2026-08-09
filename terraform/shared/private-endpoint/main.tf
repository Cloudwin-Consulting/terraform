terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The private endpoint. The DNS zone group registers its IP address
# in the given private DNS zones automatically.
resource "azurerm_private_endpoint" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  subnet_id                     = var.subnet_id
  custom_network_interface_name = "${var.name}-nic"
  tags                          = var.tags

  private_service_connection {
    name                           = "${var.name}-connection"
    private_connection_resource_id = var.private_connection_resource_id
    subresource_names              = var.subresource_names
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.private_dns_zone_ids) > 0 ? [1] : []

    content {
      name                 = "default"
      private_dns_zone_ids = var.private_dns_zone_ids
    }
  }
}

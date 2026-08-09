terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A private DNS zone with its virtual network links and records. Scope
# zones narrowly (one per hostname where a service publishes public
# names under a shared suffix) so linked networks keep resolving other
# instances of the service.

resource "azurerm_private_dns_zone" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Links the zone to virtual networks so they resolve its records.
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = var.virtual_network_links

  name                  = "link-${each.key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = each.value.virtual_network_id
  registration_enabled  = each.value.registration_enabled
  tags                  = var.tags
}

# A records in the zone.
resource "azurerm_private_dns_a_record" "this" {
  for_each = var.a_records

  name                = each.key
  zone_name           = azurerm_private_dns_zone.this.name
  resource_group_name = var.resource_group_name
  ttl                 = each.value.ttl
  records             = each.value.records
  tags                = var.tags
}

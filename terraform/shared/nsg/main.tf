terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The network security group with its inline security rules.
resource "azurerm_network_security_group" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  dynamic "security_rule" {
    for_each = var.security_rules

    content {
      name                    = security_rule.value.name
      description             = security_rule.value.description
      priority                = security_rule.value.priority
      direction               = security_rule.value.direction
      access                  = security_rule.value.access
      protocol                = security_rule.value.protocol
      source_port_range       = security_rule.value.source_port_range
      source_port_ranges      = security_rule.value.source_port_ranges
      destination_port_range  = security_rule.value.destination_port_range
      destination_port_ranges = security_rule.value.destination_port_ranges

      # Each side of a rule is either address prefixes or application
      # security groups - membership-based rules that follow the
      # workload instead of its IP ranges.
      source_address_prefix                      = security_rule.value.source_address_prefix
      source_address_prefixes                    = security_rule.value.source_address_prefixes
      source_application_security_group_ids      = security_rule.value.source_application_security_group_ids
      destination_address_prefix                 = security_rule.value.destination_address_prefix
      destination_address_prefixes               = security_rule.value.destination_address_prefixes
      destination_application_security_group_ids = security_rule.value.destination_application_security_group_ids
    }
  }
}

# Attaches the network security group to the given subnets.
resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.subnet_associations

  subnet_id                 = each.value
  network_security_group_id = azurerm_network_security_group.this.id
}

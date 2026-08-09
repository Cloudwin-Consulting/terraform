terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The firewall policy is split from the firewall itself so rule
# collection groups can be attached to it independently of the
# firewall's lifecycle.

resource "azurerm_firewall_policy" "this" {
  #checkov:skip=CKV_AZURE_220: IDPS requires the Premium SKU - the intrusion_detection block below enables it in Deny mode whenever the policy is Premium, and Azure rejects it on other SKUs.
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  sku                      = var.sku_tier
  threat_intelligence_mode = var.threat_intelligence_mode
  tags                     = var.tags

  # IDPS is a Premium-only capability; the API rejects the block on
  # Basic and Standard policies.
  dynamic "intrusion_detection" {
    for_each = var.sku_tier == "Premium" ? [1] : []

    content {
      mode = var.idps_mode
    }
  }

  dns {
    proxy_enabled = var.dns_proxy_enabled
    servers       = var.dns_servers
  }
}

# Rule collection groups on the policy, one per rule_collection_groups
# entry. Each group carries any mix of DNAT, network and application
# rule collections; Azure always processes DNAT rules first, then
# network rules, then application rules, with collection priorities
# ordering collections of the same type.
resource "azurerm_firewall_policy_rule_collection_group" "this" {
  for_each = var.rule_collection_groups

  name               = each.key
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = each.value.priority

  dynamic "network_rule_collection" {
    for_each = each.value.network_rule_collections

    content {
      name     = network_rule_collection.value.name
      priority = network_rule_collection.value.priority
      action   = network_rule_collection.value.action

      dynamic "rule" {
        for_each = network_rule_collection.value.rules

        content {
          name                  = rule.value.name
          protocols             = rule.value.protocols
          source_addresses      = rule.value.source_addresses
          source_ip_groups      = rule.value.source_ip_groups
          destination_addresses = rule.value.destination_addresses
          destination_ip_groups = rule.value.destination_ip_groups
          destination_fqdns     = rule.value.destination_fqdns
          destination_ports     = rule.value.destination_ports
        }
      }
    }
  }

  dynamic "application_rule_collection" {
    for_each = each.value.application_rule_collections

    content {
      name     = application_rule_collection.value.name
      priority = application_rule_collection.value.priority
      action   = application_rule_collection.value.action

      dynamic "rule" {
        for_each = application_rule_collection.value.rules

        content {
          name                  = rule.value.name
          source_addresses      = rule.value.source_addresses
          source_ip_groups      = rule.value.source_ip_groups
          destination_fqdns     = rule.value.destination_fqdns
          destination_fqdn_tags = rule.value.destination_fqdn_tags
          destination_urls      = rule.value.destination_urls
          web_categories        = rule.value.web_categories
          terminate_tls         = rule.value.terminate_tls

          dynamic "protocols" {
            for_each = rule.value.protocols

            content {
              type = protocols.value.type
              port = protocols.value.port
            }
          }
        }
      }
    }
  }

  dynamic "nat_rule_collection" {
    for_each = each.value.nat_rule_collections

    content {
      name     = nat_rule_collection.value.name
      priority = nat_rule_collection.value.priority
      action   = "Dnat"

      dynamic "rule" {
        for_each = nat_rule_collection.value.rules

        content {
          name                = rule.value.name
          protocols           = rule.value.protocols
          source_addresses    = rule.value.source_addresses
          destination_address = rule.value.destination_address
          destination_ports   = rule.value.destination_ports
          translated_address  = rule.value.translated_address
          translated_port     = rule.value.translated_port
        }
      }
    }
  }
}

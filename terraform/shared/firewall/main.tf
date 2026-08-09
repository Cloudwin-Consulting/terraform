terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Azure Firewall with its firewall policy managed by the firewall-policy
# sub-module. Pass DNAT, network and application rules through
# rule_collection_groups; further groups can also be attached later to
# the policy ID exposed by this module.

locals {
  # DNAT rules with a null destination_address target the firewall's
  # own public IP - the address is only known once the public IP
  # exists, so it is filled in here rather than by the caller.
  rule_collection_groups = {
    for name, group in var.rule_collection_groups : name => merge(group, {
      nat_rule_collections = [
        for collection in group.nat_rule_collections : merge(collection, {
          rules = [
            for rule in collection.rules : merge(rule, {
              destination_address = coalesce(rule.destination_address, azurerm_public_ip.this.ip_address)
            })
          ]
        })
      ]
    })
  }
}

module "policy" {
  source = "./modules/firewall-policy"

  name                     = coalesce(var.policy_name, "${var.name}-policy")
  resource_group_name      = var.resource_group_name
  location                 = var.location
  sku_tier                 = var.sku_tier
  threat_intelligence_mode = var.threat_intelligence_mode
  idps_mode                = var.idps_mode
  dns_proxy_enabled        = var.dns_proxy_enabled
  dns_servers              = var.dns_servers
  rule_collection_groups   = local.rule_collection_groups
  tags                     = var.tags
}

# The public IP the firewall requires for its frontend.
resource "azurerm_public_ip" "this" {
  name                = "${var.name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  tags                = var.tags
}

# The firewall, attached to the policy from the sub-module.
resource "azurerm_firewall" "this" {
  #checkov:skip=CKV_AZURE_216: The firewall-level threat_intel_mode attribute only applies to classic (non-policy) firewalls - here threat intelligence is enforced by the attached policy, which defaults to Deny mode.
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "AZFW_VNet"
  sku_tier            = var.sku_tier
  zones               = var.zones
  firewall_policy_id  = module.policy.id
  tags                = var.tags

  ip_configuration {
    name                 = "configuration"
    subnet_id            = var.subnet_id
    public_ip_address_id = azurerm_public_ip.this.id
  }
}

# Sends logs and metrics to Log Analytics when a workspace is
# configured. Callers that create the workspace in the same apply must
# set enable_diagnostics themselves, because the workspace ID is unknown
# until apply and cannot decide the count.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_firewall.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

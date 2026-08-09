terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A Traffic Manager profile with external endpoints. Traffic Manager is
# DNS based and its health probes come from the public internet; for
# endpoints that are only reachable privately, set always_serve_enabled
# on the endpoint so probing is bypassed.

resource "azurerm_traffic_manager_profile" "this" {
  name                   = var.name
  resource_group_name    = var.resource_group_name
  traffic_routing_method = var.traffic_routing_method
  tags                   = var.tags

  dns_config {
    relative_name = var.dns_relative_name
    ttl           = var.dns_ttl
  }

  monitor_config {
    protocol                     = var.monitor_protocol
    port                         = var.monitor_port
    path                         = var.monitor_path
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3
  }
}

# The endpoints traffic is routed across.
resource "azurerm_traffic_manager_external_endpoint" "this" {
  for_each = { for endpoint in var.external_endpoints : endpoint.name => endpoint }

  name                 = each.value.name
  profile_id           = azurerm_traffic_manager_profile.this.id
  target               = each.value.target
  endpoint_location    = each.value.location
  priority             = each.value.priority
  weight               = each.value.weight
  always_serve_enabled = each.value.always_serve_enabled
}

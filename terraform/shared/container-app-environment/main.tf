terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The environment, internal only on its delegated infrastructure
# subnet.
resource "azurerm_container_app_environment" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  # Secure defaults: the environment joins a delegated infrastructure
  # subnet and its ingress load balancer receives a private IP address
  # instead of a public one, so container apps are only reachable from
  # inside the network.
  infrastructure_subnet_id           = var.infrastructure_subnet_id
  internal_load_balancer_enabled     = var.internal_load_balancer_enabled
  infrastructure_resource_group_name = var.infrastructure_resource_group_name
  zone_redundancy_enabled            = var.zone_redundancy_enabled

  # Logs flow to Azure Monitor so the diagnostic setting below delivers
  # them with Microsoft Entra ID authentication. Sending them directly to
  # a workspace would use its shared keys, which the log-analytics module
  # disables.
  logs_destination = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? "azure-monitor" : null

  workload_profile {
    name                  = var.workload_profile_name
    workload_profile_type = var.workload_profile_type

    # Dedicated profiles scale between these node counts; Consumption
    # ignores them.
    minimum_count = var.workload_profile_minimum_count
    maximum_count = var.workload_profile_maximum_count
  }
}

# Sends the environment's logs to Log Analytics when a workspace is
# configured. Callers that create the workspace in the same apply must
# set enable_diagnostics themselves, because the workspace ID is unknown
# until apply and cannot decide the count.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_container_app_environment.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}

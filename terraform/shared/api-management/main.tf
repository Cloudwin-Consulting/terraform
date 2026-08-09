terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The instance, joined to the subnet in internal mode with a
# system-assigned identity for backend and key vault access.
resource "azurerm_api_management" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.sku_name
  zones               = var.zones
  tags                = var.tags

  # Secure default: internal virtual network mode, so the gateway,
  # developer portal and management API are only reachable on private
  # addresses inside the network.
  virtual_network_type = "Internal"

  virtual_network_configuration {
    subnet_id = var.subnet_id
  }

  identity {
    type = "SystemAssigned"
  }
}

# Sends logs and metrics to Log Analytics when a workspace is
# configured. Callers that create the workspace in the same apply must
# set enable_diagnostics themselves, because the workspace ID is unknown
# until apply and cannot decide the count.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_api_management.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A Logic App Standard on its own Workflow Standard plan. The runtime
# requires shared key access to its storage account, so back it with a
# dedicated account that has shared_access_key_enabled set, not with an
# account holding application data.

resource "azurerm_service_plan" "this" {
  name                   = var.plan_name
  resource_group_name    = var.resource_group_name
  location               = var.location
  zone_balancing_enabled = var.zone_balancing_enabled
  os_type                = "Windows"
  sku_name               = var.sku_name
  worker_count           = var.worker_count
  tags                   = var.tags
}

# The logic app, reached through a private endpoint and reaching its
# runtime storage through regional virtual network integration.
resource "azurerm_logic_app_standard" "this" {
  name                = var.logic_app_name
  resource_group_name = var.resource_group_name
  location            = var.location
  app_service_plan_id = azurerm_service_plan.this.id
  tags                = var.tags

  # Secure defaults: HTTPS only, no FTP and TLS 1.2. Expose the app
  # through a private endpoint.
  https_only                 = true
  public_network_access      = var.public_network_access
  virtual_network_subnet_id  = var.virtual_network_subnet_id
  version                    = "~4"
  storage_account_name       = var.storage_account_name
  storage_account_access_key = var.storage_account_access_key

  identity {
    type = "SystemAssigned"
  }

  site_config {
    ftps_state             = "Disabled"
    http2_enabled          = true
    min_tls_version        = "1.2"
    vnet_route_all_enabled = var.virtual_network_subnet_id != null
  }

  app_settings = var.app_settings
}

# Sends the workflow runtime's logs and metrics to Log Analytics when a
# workspace is configured. Callers that create the workspace in the same
# apply must set enable_diagnostics themselves, because the workspace ID
# is unknown until apply and cannot decide the count.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.logic_app_name}"
  target_resource_id         = azurerm_logic_app_standard.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

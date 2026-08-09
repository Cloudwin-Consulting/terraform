terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The logical server. Authentication is Microsoft Entra ID only by
# default.
resource "azurerm_mssql_server" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = "12.0"
  tags                = var.tags

  # Secure defaults: Microsoft Entra ID authentication only (no SQL
  # logins), TLS 1.2 and no public network access. Connect through a
  # private endpoint.
  minimum_tls_version           = "1.2"
  public_network_access_enabled = var.public_network_access_enabled

  azuread_administrator {
    login_username              = var.azuread_administrator.login_username
    object_id                   = var.azuread_administrator.object_id
    azuread_authentication_only = var.azuread_administrator.azuread_authentication_only
  }

  identity {
    type = "SystemAssigned"
  }
}

# Databases on the server. The default SKU is serverless; set
# auto_pause_delay_in_minutes so it actually pauses when idle.
resource "azurerm_mssql_database" "this" {
  for_each = var.databases

  name                        = each.key
  server_id                   = azurerm_mssql_server.this.id
  sku_name                    = each.value.sku_name
  max_size_gb                 = each.value.max_size_gb
  zone_redundant              = each.value.zone_redundant
  auto_pause_delay_in_minutes = each.value.auto_pause_delay_in_minutes
  tags                        = var.tags
}

# Sends each database's logs and metrics to Log Analytics when a
# workspace is configured. Callers that create the workspace in the same
# apply must set enable_diagnostics themselves, because the workspace ID
# is unknown until apply and cannot decide the for_each.
resource "azurerm_monitor_diagnostic_setting" "database" {
  for_each = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? var.databases : {}

  name                       = "diag-${each.key}"
  target_resource_id         = azurerm_mssql_database.this[each.key].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

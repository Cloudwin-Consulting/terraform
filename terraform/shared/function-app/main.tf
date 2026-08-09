terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The Linux App Service plan hosting the function app.
resource "azurerm_service_plan" "this" {
  name                   = var.plan_name
  resource_group_name    = var.resource_group_name
  location               = var.location
  zone_balancing_enabled = var.zone_balancing_enabled
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.worker_count
  tags                   = var.tags
}

locals {
  # Dedicated (Basic, Standard, PremiumV2/V3, Isolated) plans unload idle apps
  # unless Always On keeps them warm - without it a queue-triggered app
  # can sleep through its messages. Elastic Premium and Consumption
  # plans scale on events instead and reject Always On.
  dedicated_plan = can(regex("^(B|S|P|I)", var.sku_name))
  always_on      = var.always_on != null ? var.always_on : local.dedicated_plan
}

# The function app, reached through a private endpoint and reaching
# the network through regional virtual network integration.
resource "azurerm_linux_function_app" "this" {
  name                = var.function_app_name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id
  tags                = var.tags

  # Secure defaults: HTTPS only, no FTP, no public network access, and
  # the app reaches its storage account with its managed identity
  # instead of access keys.
  https_only                    = true
  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.virtual_network_subnet_id
  functions_extension_version   = "~4"

  # Host storage authenticates with the app's managed identity unless
  # an access key is supplied - Elastic Premium plans need the key so
  # the platform can create and mount the Azure Files content share,
  # which has no identity-based path.
  storage_account_name          = var.storage_account_name
  storage_account_access_key    = var.storage_account_access_key
  storage_uses_managed_identity = var.storage_account_access_key == null ? true : null

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on              = local.always_on
    ftps_state             = "Disabled"
    http2_enabled          = true
    minimum_tls_version    = "1.2"
    vnet_route_all_enabled = var.virtual_network_subnet_id != null

    dynamic "application_stack" {
      for_each = length(var.application_stack) > 0 ? [var.application_stack] : []

      content {
        dotnet_version          = lookup(application_stack.value, "dotnet_version", null)
        java_version            = lookup(application_stack.value, "java_version", null)
        node_version            = lookup(application_stack.value, "node_version", null)
        python_version          = lookup(application_stack.value, "python_version", null)
        powershell_core_version = lookup(application_stack.value, "powershell_core_version", null)
      }
    }
  }

  app_settings = var.app_settings
}

# The app's identity needs blob, queue and account management access to
# its host storage account: these are the three roles Microsoft
# documents for identity-based AzureWebJobsStorage connections. Callers
# that create the account in the same apply must set
# enable_storage_role_assignments themselves, because the account ID is
# unknown until apply and cannot decide the counts.
resource "azurerm_role_assignment" "storage_blob" {
  count = coalesce(var.enable_storage_role_assignments, var.storage_account_id != null) ? 1 : 0

  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_linux_function_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "storage_queue" {
  count = coalesce(var.enable_storage_role_assignments, var.storage_account_id != null) ? 1 : 0

  scope                = var.storage_account_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_linux_function_app.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "storage_account" {
  count = coalesce(var.enable_storage_role_assignments, var.storage_account_id != null) ? 1 : 0

  scope                = var.storage_account_id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_linux_function_app.this.identity[0].principal_id
}

# Sends logs and metrics to Log Analytics when a workspace is
# configured. Callers that create the workspace in the same apply must
# set enable_diagnostics themselves, because the workspace ID is unknown
# until apply and cannot decide the count.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.function_app_name}"
  target_resource_id         = azurerm_linux_function_app.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

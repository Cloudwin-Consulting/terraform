terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The Linux App Service plan hosting the web app.
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

# The web app, reached through a private endpoint and reaching the
# network through regional virtual network integration.
resource "azurerm_linux_web_app" "this" {
  name                = var.web_app_name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id
  tags                = var.tags

  # Secure defaults: HTTPS only, no FTP, no public network access. The app
  # is reached through a private endpoint and reaches the network through
  # regional virtual network integration.
  https_only                    = true
  public_network_access_enabled = var.public_network_access_enabled
  virtual_network_subnet_id     = var.virtual_network_subnet_id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on              = var.always_on
    ftps_state             = "Disabled"
    http2_enabled          = true
    minimum_tls_version    = "1.2"
    vnet_route_all_enabled = var.virtual_network_subnet_id != null

    # The provider only accepts these as a pair: a health check path
    # without an eviction time fails plan validation.
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_path != null ? var.health_check_eviction_time_in_min : null

    dynamic "application_stack" {
      for_each = length(var.application_stack) > 0 ? [var.application_stack] : []

      content {
        docker_image_name = lookup(application_stack.value, "docker_image_name", null)
        dotnet_version    = lookup(application_stack.value, "dotnet_version", null)
        java_version      = lookup(application_stack.value, "java_version", null)
        node_version      = lookup(application_stack.value, "node_version", null)
        php_version       = lookup(application_stack.value, "php_version", null)
        python_version    = lookup(application_stack.value, "python_version", null)
      }
    }
  }

  app_settings = var.app_settings
}

# Sends logs and metrics to Log Analytics when a workspace is
# configured. Callers that create the workspace in the same apply must
# set enable_diagnostics themselves, because the workspace ID is unknown
# until apply and cannot decide the count.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.web_app_name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

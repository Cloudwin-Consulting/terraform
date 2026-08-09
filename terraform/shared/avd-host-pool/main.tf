terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# An Azure Virtual Desktop host pool. Session hosts register into it
# with the registration token below, and users reach it through an
# application group published in a workspace. Connectivity uses the
# service's reverse connect transport: session hosts and clients both
# dial out to the AVD gateway over HTTPS, so no inbound port is ever
# opened to a session host.
resource "azurerm_virtual_desktop_host_pool" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  friendly_name       = var.friendly_name
  description         = var.description
  tags                = var.tags

  type                             = var.type
  load_balancer_type               = var.load_balancer_type
  maximum_sessions_allowed         = var.type == "Pooled" ? var.maximum_sessions_allowed : null
  personal_desktop_assignment_type = var.type == "Personal" ? var.personal_desktop_assignment_type : null
  preferred_app_group_type         = var.preferred_app_group_type
  start_vm_on_connect              = var.start_vm_on_connect
  validate_environment             = var.validate_environment
  custom_rdp_properties            = var.custom_rdp_properties
  public_network_access            = var.public_network_access

  # Restricts AVD agent updates to the given maintenance windows,
  # instead of letting the service update agents at any time.
  dynamic "scheduled_agent_updates" {
    for_each = var.scheduled_agent_updates == null ? [] : [var.scheduled_agent_updates]

    content {
      enabled                   = true
      timezone                  = scheduled_agent_updates.value.timezone
      use_session_host_timezone = scheduled_agent_updates.value.use_session_host_timezone

      dynamic "schedule" {
        for_each = scheduled_agent_updates.value.schedules

        content {
          day_of_week = schedule.value.day_of_week
          hour_of_day = schedule.value.hour_of_day
        }
      }
    }
  }
}

# The token session hosts register into the pool with. Tokens are
# short-lived by design, so this clock re-creates the registration
# info whenever the previous token expires - a plan run after the
# rotation shows the replacement. Session hosts ignore token changes
# once registered (the avd-session-host module ignores them), so
# rotation only affects hosts joining the pool.
resource "time_rotating" "registration_token" {
  rotation_days = var.registration_token_rotation_days
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "this" {
  hostpool_id     = azurerm_virtual_desktop_host_pool.this.id
  expiration_date = time_rotating.registration_token.rotation_rfc3339
}

# Sends the host pool's connection, registration, management and error
# logs to Log Analytics - the data AVD Insights builds on, delivered to
# the resource-specific WVD* tables its workbooks read. Host pools emit
# no metrics, so only logs are enabled.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                           = "diag-${var.name}"
  target_resource_id             = azurerm_virtual_desktop_host_pool.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }
}

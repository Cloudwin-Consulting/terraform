terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# An Azure Virtual Desktop application group: the unit users are
# entitled to. A Desktop group publishes each session host's full
# desktop; a RemoteApp group publishes the individual applications
# below. Users see the group once it is associated with a workspace
# (the avd-workspace module) and hold the Desktop Virtualization User
# role on it.
resource "azurerm_virtual_desktop_application_group" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  type                = var.type
  host_pool_id        = var.host_pool_id
  friendly_name       = var.friendly_name
  description         = var.description
  tags                = var.tags

  default_desktop_display_name = var.type == "Desktop" ? var.default_desktop_display_name : null
}

# The applications a RemoteApp group publishes, keyed by name.
resource "azurerm_virtual_desktop_application" "this" {
  for_each = var.applications

  name                 = each.key
  application_group_id = azurerm_virtual_desktop_application_group.this.id

  friendly_name                = each.value.friendly_name
  description                  = each.value.description
  path                         = each.value.path
  command_line_argument_policy = each.value.command_line_argument_policy
  command_line_arguments       = each.value.command_line_arguments
  show_in_portal               = each.value.show_in_portal
  icon_path                    = each.value.icon_path
  icon_index                   = each.value.icon_index
}

# Sends the application group's management and error logs to Log
# Analytics, delivered to the resource-specific WVD* tables AVD
# Insights reads. Application groups emit no metrics, so only logs are
# enabled.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                           = "diag-${var.name}"
  target_resource_id             = azurerm_virtual_desktop_application_group.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }
}

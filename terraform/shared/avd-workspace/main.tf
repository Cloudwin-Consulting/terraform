terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# An Azure Virtual Desktop workspace: the feed the AVD clients
# subscribe to. Users see the desktops and applications of every
# associated application group they are entitled to.
resource "azurerm_virtual_desktop_workspace" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  friendly_name       = var.friendly_name
  description         = var.description
  tags                = var.tags

  public_network_access_enabled = var.public_network_access_enabled
}

# Publishes the application groups through the workspace. Groups are
# keyed by a static label so groups created in the same apply - whose
# IDs are unknown at plan time - can still be associated.
resource "azurerm_virtual_desktop_workspace_application_group_association" "this" {
  for_each = var.application_group_ids

  workspace_id         = azurerm_virtual_desktop_workspace.this.id
  application_group_id = each.value
}

# Sends the workspace's feed, management and error logs to Log
# Analytics, delivered to the resource-specific WVD* tables AVD
# Insights reads. Workspaces emit no metrics, so only logs are
# enabled.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                           = "diag-${var.name}"
  target_resource_id             = azurerm_virtual_desktop_workspace.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }
}

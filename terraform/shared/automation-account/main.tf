terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# An Automation account with its runbooks and schedules. Jobs
# authenticate as the account's managed identity - the Run As accounts
# that once held a certificate are retired - and the account's own
# endpoints are reached through a private endpoint, so runbooks are
# started from inside the network.
#
# A cloud job runs on the Azure sandbox, which reaches its targets over
# the public internet. Runbooks that must act on private resources run
# on a hybrid worker inside the network instead
# (hybrid_worker_group_name on a job schedule).

locals {
  identity_type = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"
}

resource "azurerm_automation_account" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = var.sku_name
  tags                = var.tags

  # Secure defaults: no account keys (jobs and callers use Microsoft
  # Entra ID and RBAC) and no public network access. The webhook, DSC
  # and hybrid worker endpoints are reached through private endpoints.
  local_authentication_enabled  = var.local_authentication_enabled
  public_network_access_enabled = var.public_network_access_enabled

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  # Customer-managed key encryption of the account's secure assets.
  # Requires a user-assigned identity granted wrap and unwrap on a
  # purge-protected vault.
  dynamic "encryption" {
    for_each = var.customer_managed_key == null ? [] : [var.customer_managed_key]

    content {
      key_vault_key_id          = encryption.value.key_vault_key_id
      user_assigned_identity_id = encryption.value.identity_id
    }
  }
}

# The runbooks the account runs. Content comes from the repository
# (with file()) or from a published URI, so what runs is reviewed and
# versioned like the rest of the estate.
resource "azurerm_automation_runbook" "this" {
  for_each = var.runbooks

  name                    = each.key
  resource_group_name     = var.resource_group_name
  location                = var.location
  automation_account_name = azurerm_automation_account.this.name
  runbook_type            = each.value.runbook_type
  description             = each.value.description
  log_verbose             = each.value.log_verbose
  log_progress            = each.value.log_progress
  content                 = each.value.content
  tags                    = var.tags

  dynamic "publish_content_link" {
    for_each = each.value.publish_content_link == null ? [] : [each.value.publish_content_link]

    content {
      uri     = publish_content_link.value.uri
      version = publish_content_link.value.version
    }
  }
}

# The schedules runbooks are started on.
resource "azurerm_automation_schedule" "this" {
  for_each = var.schedules

  name                    = each.key
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  frequency               = each.value.frequency
  interval                = each.value.frequency == "OneTime" ? null : each.value.interval
  timezone                = each.value.timezone
  start_time              = each.value.start_time
  expiry_time             = each.value.expiry_time
  description             = each.value.description
  week_days               = each.value.frequency == "Week" ? each.value.week_days : null
  month_days              = each.value.frequency == "Month" ? each.value.month_days : null

  dynamic "monthly_occurrence" {
    for_each = each.value.frequency == "Month" && each.value.monthly_occurrence != null ? [each.value.monthly_occurrence] : []

    content {
      day        = monthly_occurrence.value.day
      occurrence = monthly_occurrence.value.occurrence
    }
  }
}

# Links a runbook to a schedule. run_on names a hybrid worker group for
# runbooks that must act on resources the Azure sandbox cannot reach.
resource "azurerm_automation_job_schedule" "this" {
  for_each = var.job_schedules

  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  runbook_name            = azurerm_automation_runbook.this[each.value.runbook_name].name
  schedule_name           = azurerm_automation_schedule.this[each.value.schedule_name].name
  parameters              = each.value.parameters
  run_on                  = each.value.hybrid_worker_group_name
}

# Sends logs and metrics to Log Analytics when a workspace is
# configured. Callers that create the workspace in the same apply must
# set enable_diagnostics themselves, because the workspace ID is unknown
# until apply and cannot decide the count.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_automation_account.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Privileged Identity Management for one role at one scope: principals
# hold an eligible assignment they activate just-in-time instead of
# standing access, governed by the role's management policy (activation
# duration, multi-factor authentication, justification, approval).
# Requires Microsoft Entra ID P2 licensing, and the deploying principal
# needs role assignment write access at the scope, e.g. Owner or
# User Access Administrator.

# A built-in role name resolves to its unscoped definition ID, prefixed
# below with the scope's subscription to form the fully qualified ID
# the Privileged Identity Management API expects.
data "azurerm_role_definition" "this" {
  count = var.role_definition_name != null ? 1 : 0

  name = var.role_definition_name
}

locals {
  role_definition_id = var.role_definition_id != null ? var.role_definition_id : format(
    "%s%s",
    regex("^/subscriptions/[^/]+", var.scope),
    data.azurerm_role_definition.this[0].id,
  )
}

# The role's management policy at this scope. The policy always exists
# in Azure with the platform defaults - this resource takes over the
# settings it specifies, and destroying it leaves the last applied
# settings in place rather than restoring the defaults.
resource "azurerm_role_management_policy" "this" {
  count = var.role_management_policy != null ? 1 : 0

  scope              = var.scope
  role_definition_id = local.role_definition_id

  dynamic "eligible_assignment_rules" {
    for_each = var.role_management_policy.eligible_assignment != null ? [var.role_management_policy.eligible_assignment] : []

    content {
      expiration_required = eligible_assignment_rules.value.expiration_required
      expire_after        = eligible_assignment_rules.value.expire_after
    }
  }

  dynamic "active_assignment_rules" {
    for_each = var.role_management_policy.active_assignment != null ? [var.role_management_policy.active_assignment] : []

    content {
      expiration_required                = active_assignment_rules.value.expiration_required
      expire_after                       = active_assignment_rules.value.expire_after
      require_multifactor_authentication = active_assignment_rules.value.require_multifactor_authentication
      require_justification              = active_assignment_rules.value.require_justification
      require_ticket_info                = active_assignment_rules.value.require_ticket_info
    }
  }

  dynamic "activation_rules" {
    for_each = var.role_management_policy.activation != null ? [var.role_management_policy.activation] : []

    content {
      maximum_duration                   = activation_rules.value.maximum_duration
      require_multifactor_authentication = activation_rules.value.require_multifactor_authentication
      require_justification              = activation_rules.value.require_justification
      require_ticket_info                = activation_rules.value.require_ticket_info
      require_approval                   = activation_rules.value.require_approval

      dynamic "approval_stage" {
        for_each = length(activation_rules.value.approvers) > 0 ? [activation_rules.value.approvers] : []

        content {
          dynamic "primary_approver" {
            for_each = approval_stage.value

            content {
              object_id = primary_approver.value.object_id
              type      = primary_approver.value.type
            }
          }
        }
      }
    }
  }
}

# Principals eligible to activate the role just-in-time. The policy
# applies first, so assignments deploy against the intended rules.
resource "azurerm_pim_eligible_role_assignment" "this" {
  for_each = var.eligible_principals

  scope              = var.scope
  role_definition_id = local.role_definition_id
  principal_id       = each.value
  justification      = var.justification

  dynamic "schedule" {
    for_each = var.assignment_schedule != null ? [var.assignment_schedule] : []

    content {
      expiration {
        duration_days  = schedule.value.duration_days
        duration_hours = schedule.value.duration_hours
        end_date_time  = schedule.value.end_date_time
      }
    }
  }

  depends_on = [azurerm_role_management_policy.this]
}

# Principals holding the role active without activating it, for the
# rare service or break-glass principals that cannot go through
# just-in-time activation. Prefer eligible assignments.
resource "azurerm_pim_active_role_assignment" "this" {
  for_each = var.active_principals

  scope              = var.scope
  role_definition_id = local.role_definition_id
  principal_id       = each.value
  justification      = var.justification

  dynamic "schedule" {
    for_each = var.assignment_schedule != null ? [var.assignment_schedule] : []

    content {
      expiration {
        duration_days  = schedule.value.duration_days
        duration_hours = schedule.value.duration_hours
        end_date_time  = schedule.value.end_date_time
      }
    }
  }

  depends_on = [azurerm_role_management_policy.this]
}

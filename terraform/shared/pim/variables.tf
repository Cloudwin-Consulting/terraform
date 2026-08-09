variable "scope" {
  description = "The scope the role is managed at: a subscription, resource group or resource ID. Scopes outside a subscription (e.g. management groups) require role_definition_id, since built-in role names resolve against the scope's subscription."
  type        = string

  validation {
    condition     = var.role_definition_id != null || can(regex("^/subscriptions/", var.scope))
    error_message = "scope must sit within a subscription when role_definition_name is used; pass role_definition_id for other scopes."
  }
}

variable "role_definition_name" {
  description = "The name of the built-in role being managed, e.g. Contributor. Exactly one of role_definition_name and role_definition_id must be set."
  type        = string
  default     = null

  validation {
    condition     = (var.role_definition_name == null) != (var.role_definition_id == null)
    error_message = "Set exactly one of role_definition_name and role_definition_id."
  }
}

variable "role_definition_id" {
  description = "The fully qualified ID of the role definition being managed, for custom roles: the subscription-prefixed form, e.g. /subscriptions/<id>/providers/Microsoft.Authorization/roleDefinitions/<id>. Exactly one of role_definition_name and role_definition_id must be set."
  type        = string
  default     = null
}

variable "eligible_principals" {
  description = "The object IDs of the principals eligible to activate the role just-in-time, keyed by a static label naming each assignment, e.g. { operations = \"<group object ID>\" }. Prefer groups, so membership changes need no deployment."
  type        = map(string)
  default     = {}
}

variable "active_principals" {
  description = "The object IDs of the principals holding the role active without activating it, keyed by a static label naming each assignment. Prefer eligible_principals; reserve active assignments for principals that cannot go through just-in-time activation."
  type        = map(string)
  default     = {}
}

variable "justification" {
  description = "The justification recorded against each assignment, shown in the Privileged Identity Management audit history."
  type        = string
  default     = "Assigned by the workload's Terraform deployment."
}

variable "assignment_schedule" {
  description = "How long the assignments last before expiring: exactly one of duration_days, duration_hours or an RFC 3339 end_date_time. Leave null for permanent assignments, which the role's management policy must allow (the platform default does)."
  type = object({
    duration_days  = optional(number)
    duration_hours = optional(number)
    end_date_time  = optional(string)
  })
  default = null

  validation {
    condition = var.assignment_schedule == null ? true : length([
      for value in [
        var.assignment_schedule.duration_days,
        var.assignment_schedule.duration_hours,
        var.assignment_schedule.end_date_time,
      ] : value if value != null
    ]) == 1
    error_message = "assignment_schedule must set exactly one of duration_days, duration_hours and end_date_time."
  }
}

variable "role_management_policy" {
  description = <<-EOT
    The role's management policy at this scope. Only the settings given are managed - everything
    else keeps its current value. activation governs just-in-time activation (maximum_duration is
    an ISO 8601 duration such as PT8H; approvers require require_approval and are User or Group
    object IDs); eligible_assignment and active_assignment govern how long assignments themselves
    may last (expire_after is P15D, P30D, P90D, P180D or P365D). Leave null to manage no policy.
  EOT
  type = object({
    activation = optional(object({
      maximum_duration                   = optional(string)
      require_multifactor_authentication = optional(bool)
      require_justification              = optional(bool)
      require_ticket_info                = optional(bool)
      require_approval                   = optional(bool)
      approvers = optional(list(object({
        object_id = string
        type      = optional(string, "Group")
      })), [])
    }))
    eligible_assignment = optional(object({
      expiration_required = optional(bool)
      expire_after        = optional(string)
    }))
    active_assignment = optional(object({
      expiration_required                = optional(bool)
      expire_after                       = optional(string)
      require_multifactor_authentication = optional(bool)
      require_justification              = optional(bool)
      require_ticket_info                = optional(bool)
    }))
  })
  default = null
}

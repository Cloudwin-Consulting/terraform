variable "scope" {
  description = "The scope the role is granted at: a management group, subscription, resource group or resource ID."
  type        = string
}

variable "role_definition_name" {
  description = "The name of the built-in role being granted, e.g. Key Vault Secrets User. Exactly one of role_definition_name and role_definition_id must be set."
  type        = string
  default     = null

  validation {
    condition     = (var.role_definition_name == null) != (var.role_definition_id == null)
    error_message = "Set exactly one of role_definition_name and role_definition_id."
  }
}

variable "role_definition_id" {
  description = "The ID of the role definition being granted, for custom roles. Exactly one of role_definition_name and role_definition_id must be set."
  type        = string
  default     = null
}

variable "principals" {
  description = "The object IDs of the principals granted the role, keyed by a static label naming each assignment, e.g. { function-app = module.function_app.principal_id }. The labels must be known at plan time; the object IDs may come from identities deployed in the same apply."
  type        = map(string)

  validation {
    condition     = length(var.principals) > 0
    error_message = "principals must contain at least one principal."
  }
}

variable "principal_type" {
  description = "The type of every principal in principals: User, Group or ServicePrincipal. Setting ServicePrincipal lets assignments to identities created moments earlier succeed without waiting for directory replication."
  type        = string
  default     = null

  validation {
    condition     = var.principal_type == null ? true : contains(["User", "Group", "ServicePrincipal"], var.principal_type)
    error_message = "principal_type must be User, Group or ServicePrincipal."
  }
}

variable "description" {
  description = "A description recorded on each assignment, shown alongside it in the portal and audit tooling."
  type        = string
  default     = null
}

variable "condition" {
  description = "An attribute-based access control condition narrowing when the role applies, e.g. to blobs carrying a tag. Requires condition_version."
  type        = string
  default     = null

  validation {
    condition     = (var.condition == null) == (var.condition_version == null)
    error_message = "condition and condition_version must be set together."
  }
}

variable "condition_version" {
  description = "The version of the condition syntax, currently 2.0."
  type        = string
  default     = null

  validation {
    condition     = var.condition_version == null ? true : var.condition_version == "2.0"
    error_message = "condition_version must be 2.0."
  }
}

variable "skip_service_principal_aad_check" {
  description = "Whether to skip checking that the principal exists in the directory, for service principals created so recently that replication has not caught up. Prefer principal_type = \"ServicePrincipal\", which conveys the same without disabling the check for other principal types."
  type        = bool
  default     = null
}

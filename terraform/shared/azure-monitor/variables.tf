variable "name" {
  description = "The name of the action group, prefixing the alert names."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the monitor resources are deployed."
  type        = string
}

variable "action_group_short_name" {
  description = "The short name of the action group shown in notifications, at most 12 characters."
  type        = string

  validation {
    condition     = length(var.action_group_short_name) >= 1 && length(var.action_group_short_name) <= 12
    error_message = "action_group_short_name must be 1-12 characters."
  }
}

variable "email_receivers" {
  description = "Email receivers of the action group, keyed by receiver name."
  type        = map(string)
  default     = {}
}

variable "alert_scope_id" {
  description = "The scope of the activity log alerts, e.g. a subscription resource ID."
  type        = string
}

variable "enable_service_health_alert" {
  description = "Whether to alert on service health incidents."
  type        = bool
  default     = true
}

variable "enable_resource_health_alert" {
  description = "Whether to alert on resource health degradation."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the monitor resources."
  type        = map(string)
  default     = {}
}

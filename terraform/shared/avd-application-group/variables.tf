variable "name" {
  description = "The name of the application group."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the application group is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the application group is deployed."
  type        = string
}

variable "type" {
  description = "The type of the application group: Desktop publishes full desktops, RemoteApp publishes the individual applications given in applications."
  type        = string
  default     = "Desktop"

  validation {
    condition     = contains(["Desktop", "RemoteApp"], var.type)
    error_message = "type must be Desktop or RemoteApp."
  }
}

variable "host_pool_id" {
  description = "The ID of the host pool the application group serves sessions from."
  type        = string
}

variable "friendly_name" {
  description = "The friendly name of the application group, shown in the AVD clients."
  type        = string
  default     = null
}

variable "description" {
  description = "A description of the application group."
  type        = string
  default     = null
}

variable "default_desktop_display_name" {
  description = "The display name of a Desktop group's published desktop, shown in the AVD clients. Ignored for RemoteApp groups."
  type        = string
  default     = null
}

variable "applications" {
  description = "The applications a RemoteApp group publishes, keyed by application name. Must be empty for Desktop groups."
  type = map(object({
    path                         = string
    friendly_name                = optional(string)
    description                  = optional(string)
    command_line_argument_policy = optional(string, "DoNotAllow")
    command_line_arguments       = optional(string)
    show_in_portal               = optional(bool, true)
    icon_path                    = optional(string)
    icon_index                   = optional(number)
  }))
  default = {}

  validation {
    condition     = var.type == "RemoteApp" || length(var.applications) == 0
    error_message = "applications can only be set on a RemoteApp application group."
  }

  validation {
    condition     = alltrue([for name, application in var.applications : contains(["DoNotAllow", "Allow", "Require"], application.command_line_argument_policy)])
    error_message = "command_line_argument_policy must be DoNotAllow, Allow or Require."
  }
}

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace the application group's logs are sent to. Leave null to skip diagnostics."
  type        = string
  default     = null
}

variable "enable_diagnostics" {
  description = "Whether to create the diagnostic setting. Defaults to whether log_analytics_workspace_id is set; set explicitly when the workspace ID comes from a resource created in the same apply, because an unknown ID cannot decide the count."
  type        = bool
  default     = null
}

variable "tags" {
  description = "Tags applied to the application group."
  type        = map(string)
  default     = {}
}

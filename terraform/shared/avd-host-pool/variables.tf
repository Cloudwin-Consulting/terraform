variable "name" {
  description = "The name of the host pool."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the host pool is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the host pool is deployed."
  type        = string
}

variable "friendly_name" {
  description = "The friendly name of the host pool, shown in the AVD clients."
  type        = string
  default     = null
}

variable "description" {
  description = "A description of the host pool."
  type        = string
  default     = null
}

variable "type" {
  description = "The type of the host pool: Pooled shares each session host between users, Personal dedicates a session host to each user."
  type        = string
  default     = "Pooled"

  validation {
    condition     = contains(["Pooled", "Personal"], var.type)
    error_message = "type must be Pooled or Personal."
  }
}

variable "load_balancer_type" {
  description = "How new sessions are distributed across a pooled host pool's hosts: BreadthFirst spreads them across all hosts, DepthFirst fills one host to maximum_sessions_allowed before the next. Personal host pools must use Persistent."
  type        = string
  default     = "BreadthFirst"

  validation {
    condition     = contains(["BreadthFirst", "DepthFirst", "Persistent"], var.load_balancer_type)
    error_message = "load_balancer_type must be BreadthFirst, DepthFirst or Persistent."
  }

  validation {
    condition     = var.type == "Personal" ? var.load_balancer_type == "Persistent" : var.load_balancer_type != "Persistent"
    error_message = "Personal host pools must use the Persistent load balancer type; pooled host pools must use BreadthFirst or DepthFirst."
  }
}

variable "maximum_sessions_allowed" {
  description = "The maximum number of user sessions per session host in a pooled host pool. Ignored for personal host pools."
  type        = number
  default     = 8

  validation {
    condition     = var.maximum_sessions_allowed >= 1 && var.maximum_sessions_allowed <= 999999
    error_message = "maximum_sessions_allowed must be between 1 and 999999."
  }
}

variable "personal_desktop_assignment_type" {
  description = "How users are assigned a personal desktop: Automatic assigns the first available host on first connection, Direct requires an administrator to assign each host. Ignored for pooled host pools."
  type        = string
  default     = "Automatic"

  validation {
    condition     = contains(["Automatic", "Direct"], var.personal_desktop_assignment_type)
    error_message = "personal_desktop_assignment_type must be Automatic or Direct."
  }
}

variable "preferred_app_group_type" {
  description = "The type of application group preferred by the host pool: Desktop publishes full desktops, RailApplications publishes individual RemoteApp applications."
  type        = string
  default     = "Desktop"

  validation {
    condition     = contains(["Desktop", "RailApplications", "None"], var.preferred_app_group_type)
    error_message = "preferred_app_group_type must be Desktop, RailApplications or None."
  }
}

variable "start_vm_on_connect" {
  description = "Whether a user connecting to the pool starts a stopped or deallocated session host. The Azure Virtual Desktop service principal must hold the Desktop Virtualization Power On Off Contributor role on the session hosts' scope (e.g. their resource group) for this to work."
  type        = bool
  default     = false
}

variable "validate_environment" {
  description = "Whether the host pool is a validation environment, receiving AVD service updates before production host pools."
  type        = bool
  default     = false
}

variable "custom_rdp_properties" {
  description = "The RDP properties applied to connections, as a semicolon-separated string. The default marks the hosts as Microsoft Entra joined (so clients on non-Entra devices can connect) and disables drive, clipboard and printer redirection out of the session."
  type        = string
  default     = "targetisaadjoined:i:1;drivestoredirect:s:;redirectclipboard:i:0;redirectprinters:i:0"
}

variable "public_network_access" {
  description = "Which of the host pool's connections traverse public AVD endpoints: Enabled, EnabledForClientsOnly, EnabledForSessionHostsOnly or Disabled. All connections are outbound over the reverse connect transport regardless; the non-Enabled values require AVD Private Link private endpoints (the private-endpoint module with the connection subresource, plus a workspace feed and one per-tenant global endpoint) before connections keep working."
  type        = string
  default     = "Enabled"

  validation {
    condition     = contains(["Enabled", "Disabled", "EnabledForClientsOnly", "EnabledForSessionHostsOnly"], var.public_network_access)
    error_message = "public_network_access must be Enabled, Disabled, EnabledForClientsOnly or EnabledForSessionHostsOnly."
  }
}

variable "scheduled_agent_updates" {
  description = "Maintenance windows the AVD agent is updated in, up to two schedules. Leave null to let the service update agents at any time."
  type = object({
    timezone                  = optional(string, "UTC")
    use_session_host_timezone = optional(bool, false)
    schedules = list(object({
      day_of_week = string
      hour_of_day = number
    }))
  })
  default = null

  validation {
    condition     = var.scheduled_agent_updates == null ? true : length(var.scheduled_agent_updates.schedules) >= 1 && length(var.scheduled_agent_updates.schedules) <= 2
    error_message = "scheduled_agent_updates takes one or two schedules."
  }
}

variable "registration_token_rotation_days" {
  description = "Days each registration token is valid for before this module issues a replacement. Azure caps registration tokens at 27 days."
  type        = number
  default     = 2

  validation {
    condition     = var.registration_token_rotation_days >= 1 && var.registration_token_rotation_days <= 27
    error_message = "registration_token_rotation_days must be between 1 and 27."
  }
}

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace the host pool's logs are sent to. Leave null to skip diagnostics."
  type        = string
  default     = null
}

variable "enable_diagnostics" {
  description = "Whether to create the diagnostic setting. Defaults to whether log_analytics_workspace_id is set; set explicitly when the workspace ID comes from a resource created in the same apply, because an unknown ID cannot decide the count."
  type        = bool
  default     = null
}

variable "tags" {
  description = "Tags applied to the host pool."
  type        = map(string)
  default     = {}
}

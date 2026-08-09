variable "name" {
  description = "The name of the container app environment."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the container app environment is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the container app environment is deployed."
  type        = string
}

variable "infrastructure_subnet_id" {
  description = "The ID of the infrastructure subnet the environment joins. Must be delegated to Microsoft.App/environments and at least a /27."
  type        = string
}

variable "internal_load_balancer_enabled" {
  description = "Whether the environment's ingress load balancer uses a private IP address. Keep enabled so container apps are only reachable from inside the network."
  type        = bool
  default     = true
}

variable "infrastructure_resource_group_name" {
  description = "The name of the platform-managed resource group that holds the environment's infrastructure. Leave null for a generated name."
  type        = string
  default     = null
}

variable "zone_redundancy_enabled" {
  description = "Whether the environment is spread across availability zones."
  type        = bool
  default     = false
}

variable "workload_profile_name" {
  description = "The name of the environment's workload profile."
  type        = string
  default     = "Consumption"
}

variable "workload_profile_type" {
  description = "The type of the environment's workload profile, e.g. Consumption or D4."
  type        = string
  default     = "Consumption"

  validation {
    condition     = contains(["Consumption", "D4", "D8", "D16", "D32", "E4", "E8", "E16", "E32"], var.workload_profile_type)
    error_message = "workload_profile_type must be Consumption or a dedicated profile such as D4 or E4."
  }

  validation {
    condition     = var.workload_profile_type == "Consumption" || (var.workload_profile_minimum_count != null && var.workload_profile_maximum_count != null)
    error_message = "Dedicated workload profiles require workload_profile_minimum_count and workload_profile_maximum_count."
  }
}

variable "workload_profile_minimum_count" {
  description = "The minimum node count of a dedicated workload profile. Required for dedicated (D and E series) profiles; ignored for Consumption."
  type        = number
  default     = null
}

variable "workload_profile_maximum_count" {
  description = "The maximum node count of a dedicated workload profile. Required for dedicated (D and E series) profiles; ignored for Consumption."
  type        = number
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "The ID of a Log Analytics workspace to send diagnostics to. Leave null to skip diagnostics."
  type        = string
  default     = null
}

variable "enable_diagnostics" {
  description = "Whether to create the diagnostic setting. Defaults to creating it when log_analytics_workspace_id is set. Set explicitly when the workspace is created in the same apply: its ID is unknown at plan time, so it cannot decide whether the setting exists."
  type        = bool
  default     = null

  validation {
    condition     = var.enable_diagnostics != true || var.log_analytics_workspace_id != null
    error_message = "enable_diagnostics requires log_analytics_workspace_id to be set."
  }
}

variable "tags" {
  description = "Tags applied to the container app environment."
  type        = map(string)
  default     = {}
}

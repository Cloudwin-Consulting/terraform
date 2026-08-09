variable "plan_name" {
  description = "The name of the App Service plan."
  type        = string
}

variable "web_app_name" {
  description = "The name of the web app. Must be globally unique as it forms the default hostname."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the app service is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the app service is deployed."
  type        = string
}

variable "sku_name" {
  description = "The SKU of the App Service plan, e.g. B1, S1, P1v3."
  type        = string
  default     = "P1v3"
}

variable "worker_count" {
  description = "The number of workers in the App Service plan."
  type        = number
  default     = 1

  validation {
    condition     = var.worker_count >= 1
    error_message = "worker_count must be at least 1."
  }
}

variable "public_network_access_enabled" {
  description = "Whether the web app is reachable over the public internet. Keep disabled and expose the app through a private endpoint."
  type        = bool
  default     = false
}

variable "virtual_network_subnet_id" {
  description = "The ID of a delegated subnet used for regional virtual network integration."
  type        = string
  default     = null
}

variable "always_on" {
  description = "Whether the web app is always loaded. Must be false on Free and Shared SKUs, which do not support Always On."
  type        = bool
  default     = true

  validation {
    condition     = !var.always_on || !contains(["F1", "D1"], var.sku_name)
    error_message = "always_on must be false on the Free (F1) and Shared (D1) SKUs: those tiers do not support Always On."
  }
}

variable "health_check_path" {
  description = "Relative path polled by the platform to assess app health."
  type        = string
  default     = null
}

variable "health_check_eviction_time_in_min" {
  description = "Minutes an instance may stay unhealthy before the platform removes it from rotation. Applied only alongside health_check_path, which the provider requires it to accompany."
  type        = number
  default     = 10

  validation {
    condition     = var.health_check_eviction_time_in_min >= 2 && var.health_check_eviction_time_in_min <= 10
    error_message = "health_check_eviction_time_in_min must be between 2 and 10 minutes."
  }
}

variable "application_stack" {
  description = "The runtime stack, e.g. { node_version = \"20-lts\" } or { dotnet_version = \"8.0\" }. Supported keys: docker_image_name, dotnet_version, java_version, node_version, php_version, python_version."
  type        = map(string)
  default     = {}
}

variable "app_settings" {
  description = "Application settings applied to the web app."
  type        = map(string)
  default     = {}
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
  description = "Tags applied to the app service resources."
  type        = map(string)
  default     = {}
}

variable "zone_balancing_enabled" {
  description = "Whether plan instances spread across availability zones. Requires a Premium SKU and at least two workers, ideally a multiple of the zone count."
  type        = bool
  default     = false

  validation {
    condition     = !var.zone_balancing_enabled || var.worker_count >= 2
    error_message = "zone_balancing_enabled requires worker_count of at least 2: a single instance cannot spread across availability zones."
  }

  validation {
    condition     = !var.zone_balancing_enabled || can(regex("^(P[0-9]+m?v[2-4]|I[0-9]+v2)$", var.sku_name))
    error_message = "zone_balancing_enabled requires a zone-capable plan SKU (Premium v2/v3/v4 or Isolated v2): Basic and Standard plans do not support zone redundancy."
  }
}

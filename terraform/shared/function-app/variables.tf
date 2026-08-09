variable "plan_name" {
  description = "The name of the App Service plan."
  type        = string
}

variable "function_app_name" {
  description = "The name of the function app. Must be globally unique as it forms the default hostname."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the function app is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the function app is deployed."
  type        = string
}

variable "sku_name" {
  description = "The SKU of the App Service plan. Elastic Premium (EP1 and up) supports virtual network integration with scale to zero."
  type        = string
  default     = "EP1"
}

variable "always_on" {
  description = "Whether the app stays loaded when idle. Defaults to true on dedicated (Basic/Standard/Premium/Isolated) plans, which otherwise unload idle apps and can sleep through queue messages, and false on Elastic Premium and Consumption plans, which scale on events and reject Always On."
  type        = bool
  default     = null
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

variable "storage_account_name" {
  description = "The name of the storage account backing the function app."
  type        = string
}

variable "storage_account_id" {
  description = "The ID of the storage account backing the function app, used to grant the app's identity blob access. Leave null to manage the role assignment elsewhere."
  type        = string
  default     = null
}

variable "enable_storage_role_assignments" {
  description = "Whether to create the role assignments granting the app's identity access to the host storage account. Defaults to creating them when storage_account_id is set. Set explicitly when the account is created in the same apply: its ID is unknown at plan time, so it cannot decide whether the assignments exist."
  type        = bool
  default     = null

  validation {
    condition     = var.enable_storage_role_assignments != true || var.storage_account_id != null
    error_message = "enable_storage_role_assignments requires storage_account_id to be set."
  }
}

variable "storage_account_access_key" {
  description = "The access key of the host storage account. Required on Elastic Premium plans, whose Azure Files content share mounts with shared-key authorisation only; leave null on dedicated plans to keep host storage identity-based."
  type        = string
  default     = null
  sensitive   = true
}

variable "public_network_access_enabled" {
  description = "Whether the function app is reachable over the public internet. Keep disabled and expose the app through a private endpoint."
  type        = bool
  default     = false
}

variable "virtual_network_subnet_id" {
  description = "The ID of a delegated subnet used for regional virtual network integration."
  type        = string
  default     = null
}

variable "application_stack" {
  description = "The runtime stack, e.g. { node_version = \"20\" } or { dotnet_version = \"8.0\" }. Supported keys: dotnet_version, java_version, node_version, python_version, powershell_core_version."
  type        = map(string)
  default     = {}
}

variable "app_settings" {
  description = "Application settings applied to the function app."
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
  description = "Tags applied to the function app resources."
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
    condition     = !var.zone_balancing_enabled || can(regex("^(EP[1-3]|P[0-9]+m?v[2-4])$", var.sku_name))
    error_message = "zone_balancing_enabled requires a zone-capable plan SKU (Elastic Premium or Premium v2/v3/v4): Basic and Standard plans do not support zone redundancy."
  }
}

variable "plan_name" {
  description = "The name of the Workflow Standard plan."
  type        = string
}

variable "logic_app_name" {
  description = "The name of the logic app. Must be globally unique as it forms the default hostname."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the logic app is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the logic app is deployed."
  type        = string
}

variable "sku_name" {
  description = "The SKU of the Workflow Standard plan, e.g. WS1, WS2 or WS3."
  type        = string
  default     = "WS1"

  validation {
    condition     = contains(["WS1", "WS2", "WS3"], var.sku_name)
    error_message = "sku_name must be WS1, WS2 or WS3."
  }
}

variable "storage_account_name" {
  description = "The name of the storage account backing the logic app runtime. The account must have shared key access enabled."
  type        = string
}

variable "storage_account_access_key" {
  description = "An access key of the storage account backing the logic app runtime."
  type        = string
  sensitive   = true
}

variable "public_network_access" {
  description = "Whether the logic app is reachable over the public internet: Enabled or Disabled. Keep disabled and expose the app through a private endpoint."
  type        = string
  default     = "Disabled"
}

variable "virtual_network_subnet_id" {
  description = "The ID of a delegated subnet used for regional virtual network integration."
  type        = string
  default     = null
}

variable "app_settings" {
  description = "Application settings applied to the logic app."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to the logic app resources."
  type        = map(string)
  default     = {}
}

variable "worker_count" {
  description = "The number of plan instances. Zone balancing needs at least two."
  type        = number
  default     = 1

  validation {
    condition     = var.worker_count >= 1
    error_message = "worker_count must be at least 1."
  }
}

variable "zone_balancing_enabled" {
  description = "Whether plan instances spread across availability zones. Requires at least two workers, ideally a multiple of the zone count."
  type        = bool
  default     = false

  validation {
    condition     = !var.zone_balancing_enabled || var.worker_count >= 2
    error_message = "zone_balancing_enabled requires worker_count of at least 2: a single instance cannot spread across availability zones."
  }
}

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace the logic app's diagnostics are sent to. Leave null to skip diagnostics."
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

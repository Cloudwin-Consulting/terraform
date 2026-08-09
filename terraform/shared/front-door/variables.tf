variable "name" {
  description = "The name of the Front Door profile."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the profile is deployed."
  type        = string
}

variable "sku_name" {
  description = "The SKU of the profile. Premium_AzureFrontDoor is required for private link origins."
  type        = string
  default     = "Premium_AzureFrontDoor"

  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.sku_name)
    error_message = "sku_name must be Standard_AzureFrontDoor or Premium_AzureFrontDoor."
  }
}

variable "response_timeout_seconds" {
  description = "Seconds Front Door waits for a response from the origin."
  type        = number
  default     = 60
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
  description = "Tags applied to the profile."
  type        = map(string)
  default     = {}
}

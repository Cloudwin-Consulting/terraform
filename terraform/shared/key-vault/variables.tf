variable "name" {
  description = "The name of the key vault. Must be globally unique, 3-24 alphanumeric characters and hyphens, starting with a letter."
  type        = string

  validation {
    condition = (
      can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name)) &&
      !can(regex("--", var.name))
    )
    error_message = "The key vault name must be 3-24 characters of letters, numbers and hyphens, start with a letter, end alphanumeric and contain no consecutive hyphens."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the key vault is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the key vault is deployed."
  type        = string
}

variable "sku_name" {
  description = "The SKU of the key vault, either standard or premium."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be standard or premium."
  }
}

variable "purge_protection_enabled" {
  description = "Whether purge protection is enabled. Keep enabled so soft-deleted vaults and secrets cannot be permanently removed before the retention period ends."
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Days soft-deleted vaults and secrets are retained for recovery."
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "public_network_access_enabled" {
  description = "Whether the key vault is reachable over the public internet. Keep disabled and access the data plane through private endpoints."
  type        = bool
  default     = false
}

variable "secrets_officer_principal_ids" {
  description = "Principal IDs granted the Key Vault Secrets Officer role to create and manage secrets from inside the network, e.g. an administrators group."
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "The ID of a Log Analytics workspace to send audit diagnostics to. Leave null to skip diagnostics."
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
  description = "Tags applied to the key vault."
  type        = map(string)
  default     = {}
}

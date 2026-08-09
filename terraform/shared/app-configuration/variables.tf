variable "name" {
  description = "The name of the App Configuration store. Must be globally unique as it forms the default hostname."
  type        = string

  validation {
    condition     = length(var.name) >= 5 && length(var.name) <= 50 && can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.name))
    error_message = "The store name must be 5-50 characters of letters, numbers and hyphens, starting and ending alphanumeric."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the store is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the store is deployed."
  type        = string
}

variable "sku" {
  description = "The SKU of the store. At least standard is required for the private endpoints and purge protection the module always configures."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku)
    error_message = "sku must be standard or premium: the free tier does not support the private endpoints or purge protection the module always configures."
  }
}

variable "public_network_access" {
  description = "Whether the store is reachable over the public internet: Enabled or Disabled. Keep disabled and access it through a private endpoint."
  type        = string
  default     = "Disabled"

  validation {
    condition     = contains(["Enabled", "Disabled"], var.public_network_access)
    error_message = "public_network_access must be Enabled or Disabled."
  }
}

variable "purge_protection_enabled" {
  description = "Whether purge protection is enabled, so soft-deleted stores cannot be permanently removed before the retention period ends."
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Days soft-deleted stores are retained for recovery."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 7
    error_message = "soft_delete_retention_days must be between 1 and 7."
  }
}

variable "tags" {
  description = "Tags applied to the store."
  type        = map(string)
  default     = {}
}

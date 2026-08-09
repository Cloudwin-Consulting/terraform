variable "name" {
  description = "The name of the Recovery Services vault."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the vault is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the vault is deployed."
  type        = string
}

variable "public_network_access_enabled" {
  description = "Whether the vault is reachable over the public internet. Keep disabled and reach it through a private endpoint (AzureBackup subresource with the geo-specific backup, blob and queue private DNS zones)."
  type        = bool
  default     = false
}

variable "sku" {
  description = "The SKU of the vault."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "RS0"], var.sku)
    error_message = "sku must be Standard or RS0."
  }
}

variable "storage_mode_type" {
  description = "The storage redundancy of the vault: LocallyRedundant, ZoneRedundant or GeoRedundant."
  type        = string
  default     = "GeoRedundant"

  validation {
    condition     = contains(["GeoRedundant", "LocallyRedundant", "ZoneRedundant"], var.storage_mode_type)
    error_message = "storage_mode_type must be GeoRedundant, LocallyRedundant or ZoneRedundant."
  }
}

variable "backup_timezone" {
  description = "The timezone the backup schedule is evaluated in."
  type        = string
  default     = "UTC"
}

variable "daily_backup_time" {
  description = "The time of day the daily backup runs, in HH:MM."
  type        = string
  default     = "23:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.daily_backup_time))
    error_message = "daily_backup_time must be HH:MM, e.g. 23:00."
  }
}

variable "daily_retention_days" {
  description = "Days daily backups are retained."
  type        = number
  default     = 7

  validation {
    condition     = var.daily_retention_days >= 7 && var.daily_retention_days <= 9999
    error_message = "daily_retention_days must be between 7 and 9999."
  }
}

variable "tags" {
  description = "Tags applied to the vault."
  type        = map(string)
  default     = {}
}

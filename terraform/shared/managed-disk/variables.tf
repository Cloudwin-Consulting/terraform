variable "name" {
  description = "The name of the managed disk."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the disk is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the disk is deployed."
  type        = string
}

variable "storage_account_type" {
  description = "The storage type of the disk, e.g. StandardSSD_LRS, Premium_LRS or Premium_ZRS."
  type        = string
  default     = "StandardSSD_LRS"

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "StandardSSD_ZRS", "Premium_LRS", "Premium_ZRS", "PremiumV2_LRS", "UltraSSD_LRS"], var.storage_account_type)
    error_message = "storage_account_type must be a valid managed disk type, e.g. StandardSSD_LRS, Premium_LRS or Premium_ZRS."
  }
}

variable "create_option" {
  description = "How the disk is created. Empty for a new blank disk."
  type        = string
  default     = "Empty"
}

variable "disk_size_gb" {
  description = "The size of the disk in GB."
  type        = number

  validation {
    condition     = var.disk_size_gb >= 1 && var.disk_size_gb <= 65536
    error_message = "disk_size_gb must be between 1 and 65536."
  }
}

variable "zone" {
  description = "The availability zone of the disk. Must match the zone of the virtual machine it attaches to."
  type        = string
  default     = null

  validation {
    condition     = var.zone == null || contains(["1", "2", "3"], coalesce(var.zone, "1"))
    error_message = "zone must be 1, 2 or 3."
  }
}

variable "tier" {
  description = "The performance tier of the disk, e.g. P30. Leave null for the size's default tier."
  type        = string
  default     = null
}

variable "network_access_policy" {
  description = "Whether the disk's data plane (exports and SAS access) is reachable: DenyAll, AllowAll or AllowPrivate (with a disk access resource)."
  type        = string
  default     = "DenyAll"

  validation {
    condition     = contains(["AllowAll", "AllowPrivate", "DenyAll"], var.network_access_policy)
    error_message = "network_access_policy must be AllowAll, AllowPrivate or DenyAll."
  }

  validation {
    condition     = var.network_access_policy != "AllowPrivate" || var.disk_access_id != null
    error_message = "network_access_policy AllowPrivate requires disk_access_id: private disk exports flow through a disk access resource."
  }
}

variable "disk_access_id" {
  description = "The ID of the disk access resource private disk exports flow through. Required when network_access_policy is AllowPrivate."
  type        = string
  default     = null
}

variable "public_network_access_enabled" {
  description = "Whether the disk's data plane is reachable over the public internet. Keep disabled."
  type        = bool
  default     = false
}

variable "disk_encryption_set_id" {
  description = "The ID of a disk encryption set for customer-managed key encryption, e.g. from the disk-encryption-set module. Leave null for platform-managed keys."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the disk."
  type        = map(string)
  default     = {}
}

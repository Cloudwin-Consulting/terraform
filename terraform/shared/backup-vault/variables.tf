variable "name" {
  description = "The name of the backup vault."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the backup vault is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the backup vault is deployed."
  type        = string
}

variable "redundancy" {
  description = "The redundancy of the backup vault: LocallyRedundant, ZoneRedundant or GeoRedundant."
  type        = string
  default     = "GeoRedundant"

  validation {
    condition     = contains(["LocallyRedundant", "ZoneRedundant", "GeoRedundant"], var.redundancy)
    error_message = "redundancy must be LocallyRedundant, ZoneRedundant or GeoRedundant."
  }
}

variable "blob_operational_retention_duration" {
  description = "The ISO 8601 retention duration of the default blob backup policy, e.g. P30D."
  type        = string
  default     = "P30D"

  validation {
    condition     = can(regex("^P", var.blob_operational_retention_duration))
    error_message = "blob_operational_retention_duration must be an ISO 8601 duration, e.g. P30D."
  }
}

variable "tags" {
  description = "Tags applied to the backup vault."
  type        = map(string)
  default     = {}
}

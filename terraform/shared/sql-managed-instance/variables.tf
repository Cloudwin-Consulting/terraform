variable "name" {
  description = "The name of the SQL managed instance. Must be globally unique as it forms the default hostname."
  type        = string

  validation {
    condition     = length(var.name) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "The instance name must be up to 63 lowercase letters, numbers and hyphens, starting and ending alphanumeric."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the instance is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the instance is deployed."
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet delegated to Microsoft.Sql/managedInstances the instance joins."
  type        = string
}

variable "sku_name" {
  description = "The SKU of the instance, e.g. GP_Gen5 or BC_Gen5."
  type        = string
  default     = "GP_Gen5"
}

variable "vcores" {
  description = "The number of vCores of the instance."
  type        = number
  default     = 4

  validation {
    condition     = contains([4, 8, 16, 24, 32, 40, 64, 80], var.vcores)
    error_message = "vcores must be one of 4, 8, 16, 24, 32, 40, 64 or 80."
  }
}

variable "storage_size_in_gb" {
  description = "The storage size of the instance in GB."
  type        = number
  default     = 32

  validation {
    condition     = var.storage_size_in_gb >= 32 && var.storage_size_in_gb <= 16384 && var.storage_size_in_gb % 32 == 0
    error_message = "storage_size_in_gb must be a multiple of 32 between 32 and 16384."
  }
}

variable "license_type" {
  description = "The license type of the instance: BasePrice (with Azure Hybrid Benefit) or LicenseIncluded."
  type        = string
  default     = "BasePrice"

  validation {
    condition     = contains(["BasePrice", "LicenseIncluded"], var.license_type)
    error_message = "license_type must be BasePrice or LicenseIncluded."
  }
}

variable "collation" {
  description = "The collation of the instance."
  type        = string
  default     = "SQL_Latin1_General_CP1_CI_AS"
}

variable "zone_redundant_enabled" {
  description = "Whether the instance is spread across availability zones."
  type        = bool
  default     = false
}

variable "administrator_login" {
  description = "The SQL administrator login of the instance, required at creation. With azuread_authentication_only it cannot be used to sign in."
  type        = string
  default     = "sqlmiadmin"
}

variable "administrator_password" {
  description = "The SQL administrator password of the instance. Generate it rather than committing it to source control."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.administrator_password) >= 16 && length(var.administrator_password) <= 128
    error_message = "SQL Managed Instance administrator passwords must be between 16 and 128 characters."
  }
}

variable "azuread_administrator" {
  description = "The Microsoft Entra ID administrator of the instance, e.g. a database administrators group. Set azuread_authentication_only to disable the SQL administrator login."
  type = object({
    login_username              = string
    object_id                   = string
    azuread_authentication_only = optional(bool, true)
  })
  default = null
}

variable "tags" {
  description = "Tags applied to the instance."
  type        = map(string)
  default     = {}
}

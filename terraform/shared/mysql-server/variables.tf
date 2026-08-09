variable "name" {
  description = "The name of the MySQL flexible server. Must be globally unique as it forms the default hostname."
  type        = string

  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "The server name must be 3-63 lowercase letters, numbers and hyphens, starting and ending alphanumeric."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the server is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the server is deployed."
  type        = string
}

variable "mysql_version" {
  description = "The MySQL version of the server."
  type        = string
  default     = "8.0.21"
}

variable "sku_name" {
  description = "The SKU of the server, e.g. B_Standard_B1ms or GP_Standard_D2ds_v4."
  type        = string
  default     = "GP_Standard_D2ds_v4"
}

variable "administrator_login" {
  description = "The administrator login of the server."
  type        = string
  default     = "mysqladmin"
}

variable "administrator_password" {
  description = "The administrator password of the server. Generate it rather than committing it to source control."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.administrator_password) >= 8 && length(var.administrator_password) <= 128
    error_message = "MySQL administrator passwords must be between 8 and 128 characters."
  }
}

variable "zone" {
  description = "The availability zone of the server."
  type        = string
  default     = null
}

variable "backup_retention_days" {
  description = "Days backups are retained."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "geo_redundant_backup_enabled" {
  description = "Whether backups are geo-redundant."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Whether the server is reachable over the public internet. Keep disabled and use a delegated subnet."
  type        = bool
  default     = false
}

variable "delegated_subnet_id" {
  description = "The ID of a subnet delegated to Microsoft.DBforMySQL/flexibleServers, making the server private. Requires private_dns_zone_id."
  type        = string
  default     = null

  validation {
    condition     = var.delegated_subnet_id == null || var.private_dns_zone_id != null
    error_message = "delegated_subnet_id requires private_dns_zone_id: MySQL Flexible Server needs its private DNS zone when deployed into a delegated subnet."
  }
}

variable "private_dns_zone_id" {
  description = "The ID of a privatelink.mysql.database.azure.com private DNS zone. Required with delegated_subnet_id."
  type        = string
  default     = null
}

variable "databases" {
  description = "Databases to create on the server."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the server resources."
  type        = map(string)
  default     = {}
}

variable "high_availability" {
  description = "Zone-redundant or same-zone high availability with a standby server. Requires a General Purpose or Memory Optimized SKU. Leave null for a single server."
  type = object({
    mode                      = string
    standby_availability_zone = optional(string)
  })
  default = null

  validation {
    condition     = var.high_availability == null || !can(regex("^B_", var.sku_name))
    error_message = "high_availability requires a General Purpose or Memory Optimized SKU: MySQL Flexible Server does not support HA on the Burstable tier."
  }
}

variable "name" {
  description = "The name of the PostgreSQL flexible server. Must be globally unique as it forms the default hostname."
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

variable "postgresql_version" {
  description = "The PostgreSQL version of the server."
  type        = string
  default     = "16"
}

variable "sku_name" {
  description = "The SKU of the server, e.g. B_Standard_B1ms or GP_Standard_D2s_v3."
  type        = string
  default     = "GP_Standard_D2s_v3"
}

variable "storage_mb" {
  description = "The storage of the server in MB."
  type        = number
  default     = 32768
}

variable "administrator_login" {
  description = "The administrator login of the server."
  type        = string
  default     = "psqladmin"
}

variable "administrator_password" {
  description = "The administrator password of the server. Generate it rather than committing it to source control."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.administrator_password) >= 8 && length(var.administrator_password) <= 128
    error_message = "PostgreSQL administrator passwords must be between 8 and 128 characters."
  }
}

variable "entra_authentication_enabled" {
  description = "Whether Microsoft Entra ID authentication is enabled alongside password authentication."
  type        = bool
  default     = true
}

variable "entra_administrator" {
  description = "The Microsoft Entra ID administrator that bootstraps database roles, e.g. a database administrators group. Requires entra_authentication_enabled."
  type = object({
    object_id      = string
    principal_name = string
    principal_type = optional(string, "Group")
  })
  default = null

  validation {
    condition     = var.entra_administrator == null || contains(["User", "Group", "ServicePrincipal"], try(var.entra_administrator.principal_type, "Group"))
    error_message = "entra_administrator principal_type must be User, Group or ServicePrincipal."
  }
  validation {
    condition     = var.entra_administrator == null || var.entra_authentication_enabled
    error_message = "entra_administrator requires entra_authentication_enabled: the administrator cannot be created while Active Directory authentication is disabled."
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
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
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
  description = "The ID of a subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers, making the server private. Requires private_dns_zone_id."
  type        = string
  default     = null

  validation {
    condition     = var.delegated_subnet_id == null || var.private_dns_zone_id != null
    error_message = "delegated_subnet_id requires private_dns_zone_id: PostgreSQL Flexible Server needs its private DNS zone when deployed into a delegated subnet."
  }
}

variable "private_dns_zone_id" {
  description = "The ID of a privatelink.postgres.database.azure.com private DNS zone. Required with delegated_subnet_id."
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
    error_message = "high_availability requires a General Purpose or Memory Optimized SKU: PostgreSQL Flexible Server does not support HA on the Burstable tier."
  }
}

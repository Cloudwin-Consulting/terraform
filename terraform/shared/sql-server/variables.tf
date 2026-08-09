variable "name" {
  description = "The name of the SQL server. Must be globally unique as it forms the default hostname."
  type        = string

  validation {
    condition     = length(var.name) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "The server name must be up to 63 lowercase letters, numbers and hyphens, starting and ending alphanumeric."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the SQL server is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the SQL server is deployed."
  type        = string
}

variable "azuread_administrator" {
  description = "The Microsoft Entra ID administrator of the server, e.g. a database administrators group."
  type = object({
    login_username              = string
    object_id                   = string
    azuread_authentication_only = optional(bool, true)
  })
}

variable "public_network_access_enabled" {
  description = "Whether the SQL server is reachable over the public internet. Keep disabled and connect through a private endpoint."
  type        = bool
  default     = false
}

variable "databases" {
  description = "Databases to create on the server, keyed by name. auto_pause_delay_in_minutes only applies to serverless SKUs (which pause when idle); leave it null on provisioned SKUs."
  type = map(object({
    sku_name                    = optional(string, "GP_S_Gen5_1")
    max_size_gb                 = optional(number, 32)
    zone_redundant              = optional(bool, false)
    auto_pause_delay_in_minutes = optional(number)
  }))
  default = {}

  validation {
    condition     = alltrue([for name, database in var.databases : database.max_size_gb >= 1])
    error_message = "Database max_size_gb must be at least 1."
  }

  validation {
    condition = alltrue([
      for database_name, database in var.databases :
      upper(database.sku_name) != "BASIC" ||
      database.max_size_gb <= 2
    ])

    error_message = "Azure SQL Basic databases support a maximum size of 2 GB."
  }

  validation {
    condition     = alltrue([for name, database in var.databases : database.auto_pause_delay_in_minutes == null || can(regex("_S_", database.sku_name))])
    error_message = "auto_pause_delay_in_minutes only applies to serverless SKUs, e.g. GP_S_Gen5_1."
  }

  validation {
    condition = alltrue([
      for _, database in var.databases :
      strcontains(upper(database.sku_name), "_S_") ||
      database.auto_pause_delay_in_minutes == null
    ])

    error_message = "auto_pause_delay_in_minutes can only be set for serverless SKUs, such as GP_S_Gen5_1."
  }
}

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace each database's diagnostics are sent to. Leave null to skip diagnostics."
  type        = string
  default     = null
}

variable "enable_diagnostics" {
  description = "Whether to create the per-database diagnostic settings. Defaults to creating them when log_analytics_workspace_id is set. Set explicitly when the workspace is created in the same apply: its ID is unknown at plan time, so it cannot decide whether the settings exist."
  type        = bool
  default     = null

  validation {
    condition     = var.enable_diagnostics != true || var.log_analytics_workspace_id != null
    error_message = "enable_diagnostics requires log_analytics_workspace_id to be set."
  }
}

variable "tags" {
  description = "Tags applied to the SQL server resources."
  type        = map(string)
  default     = {}
}

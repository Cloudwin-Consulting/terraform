variable "name" {
  description = "The name of the Cosmos DB account. Must be globally unique as it forms the default hostname."
  type        = string

  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 44 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "The account name must be 3-44 lowercase letters, numbers and hyphens, starting and ending alphanumeric."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the account is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the account is deployed."
  type        = string
}

variable "consistency_level" {
  description = "The consistency level of the account."
  type        = string
  default     = "Session"

  validation {
    condition     = contains(["Strong", "BoundedStaleness", "Session", "ConsistentPrefix", "Eventual"], var.consistency_level)
    error_message = "consistency_level must be Strong, BoundedStaleness, Session, ConsistentPrefix or Eventual."
  }
}

variable "local_authentication_disabled" {
  description = "Whether key-based authentication is disabled. Keep disabled and grant access with Microsoft Entra ID and the Cosmos DB data plane RBAC roles."
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Whether the account is reachable over the public internet. Keep disabled and access data through a private endpoint."
  type        = bool
  default     = false
}

variable "automatic_failover_enabled" {
  description = "Whether the account fails over automatically across regions. Requires at least one entry in additional_geo_locations to fail over to."
  type        = bool
  default     = false

  validation {
    condition     = !var.automatic_failover_enabled || length(var.additional_geo_locations) > 0
    error_message = "automatic_failover_enabled requires at least one additional_geo_locations entry: a single-region account has nowhere to fail over to."
  }
}

variable "additional_geo_locations" {
  description = "Secondary regions the account replicates to, in failover priority order after the primary."
  type = list(object({
    location       = string
    zone_redundant = optional(bool, false)
  }))
  default = []
}

variable "zone_redundant" {
  description = "Whether the primary region is zone redundant."
  type        = bool
  default     = false
}

variable "sql_databases" {
  description = "SQL API databases to create in the account. Containers are application-specific and created by the consuming stack."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the account."
  type        = map(string)
  default     = {}
}

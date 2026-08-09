variable "name" {
  description = "The name of the Redis cache. Must be globally unique as it forms the default hostname."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the cache is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the cache is deployed."
  type        = string
}

variable "sku_name" {
  description = "The SKU of the cache: Basic, Standard or Premium."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku_name)
    error_message = "sku_name must be Basic, Standard or Premium."
  }
}

variable "family" {
  description = "The SKU family of the cache: C for Basic/Standard, P for Premium."
  type        = string
  default     = "C"

  validation {
    condition     = (var.sku_name == "Premium") == (var.family == "P") && contains(["C", "P"], var.family)
    error_message = "family must be C for Basic/Standard and P for Premium."
  }
}

variable "capacity" {
  description = "The size of the cache within its family: C0-C6 for Basic/Standard, P1-P5 for Premium."
  type        = number
  default     = 1

  validation {
    condition     = var.family == "P" ? (var.capacity >= 1 && var.capacity <= 5) : (var.capacity >= 0 && var.capacity <= 6)
    error_message = "capacity must be 1-5 for the Premium (P) family and 0-6 for the C family."
  }
}

variable "redis_version" {
  description = "The major Redis version of the cache."
  type        = string
  default     = "6"
}

variable "public_network_access_enabled" {
  description = "Whether the cache is reachable over the public internet. Keep disabled and access it through a private endpoint."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the cache."
  type        = map(string)
  default     = {}
}

variable "zones" {
  description = "Availability zones of the deployment, e.g. [\"1\", \"2\", \"3\"] for zone redundancy. Requires the Premium SKU. Leave null for a regional deployment."
  type        = list(string)
  default     = null

  validation {
    condition     = var.zones == null || var.sku_name == "Premium"
    error_message = "zones requires the Premium SKU: Basic and Standard caches do not support zone redundancy."
  }
}

variable "access_keys_authentication_enabled" {
  description = "Whether access key authentication is allowed. Keep disabled so Microsoft Entra ID is the only authentication path."
  type        = bool
  default     = false
}

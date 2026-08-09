variable "name" {
  description = "The name of the Event Hubs namespace. Must be globally unique as it forms the default hostname."
  type        = string

  validation {
    condition     = length(var.name) >= 6 && length(var.name) <= 50 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.name))
    error_message = "The namespace name must be 6-50 characters, start with a letter, end alphanumeric and contain only letters, numbers and hyphens."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the namespace is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the namespace is deployed."
  type        = string
}

variable "sku" {
  description = "The SKU of the namespace: Standard or Premium. Private endpoints require Standard or above."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.sku)
    error_message = "sku must be Standard or Premium; private endpoints are not supported on Basic."
  }
}

variable "capacity" {
  description = "The throughput units (Standard) or processing units (Premium) of the namespace."
  type        = number
  default     = 1
}

variable "auto_inflate_enabled" {
  description = "Whether throughput units scale up automatically on the Standard SKU. Requires maximum_throughput_units."
  type        = bool
  default     = false

  validation {
    condition     = !var.auto_inflate_enabled || var.maximum_throughput_units != null
    error_message = "maximum_throughput_units must be set when auto_inflate_enabled is true."
  }

  validation {
    condition     = !var.auto_inflate_enabled || var.sku == "Standard"
    error_message = "auto_inflate_enabled only applies to the Standard SKU: Premium namespaces scale with processing units instead."
  }
}

variable "maximum_throughput_units" {
  description = "The throughput unit ceiling auto-inflate scales up to."
  type        = number
  default     = null

  validation {
    condition     = var.maximum_throughput_units == null || coalesce(var.maximum_throughput_units, 1) >= 1 && coalesce(var.maximum_throughput_units, 1) <= 40
    error_message = "maximum_throughput_units must be between 1 and 40."
  }
}

variable "public_network_access_enabled" {
  description = "Whether the namespace is reachable over the public internet. Keep disabled and access it through a private endpoint."
  type        = bool
  default     = false
}

variable "event_hubs" {
  description = "Event hubs to create in the namespace, keyed by name."
  type = map(object({
    partition_count   = optional(number, 2)
    message_retention = optional(number, 1)
  }))
  default = {}

  validation {
    condition     = alltrue([for name, hub in var.event_hubs : hub.partition_count >= 1 && hub.partition_count <= 32 && hub.message_retention >= 1 && hub.message_retention <= (var.sku == "Standard" ? 7 : 90)])
    error_message = "Event hubs must have 1-32 partitions, and message retention of 1-7 days on Standard (up to 90 on Premium)."
  }
}

variable "tags" {
  description = "Tags applied to the namespace."
  type        = map(string)
  default     = {}
}

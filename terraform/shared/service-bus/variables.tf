variable "name" {
  description = "The name of the Service Bus namespace. Must be globally unique as it forms the default hostname."
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
  description = "The SKU of the namespace. Premium is required for private endpoints and disabled public network access."
  type        = string
  default     = "Premium"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be Basic, Standard or Premium."
  }
}

variable "capacity" {
  description = "The number of messaging units for the Premium SKU. Ignored on Basic and Standard, which only accept a capacity of zero."
  type        = number
  default     = 1

  validation {
    condition     = var.sku != "Premium" || contains([1, 2, 4, 8, 16], var.capacity)
    error_message = "Premium namespaces support 1, 2, 4, 8 or 16 messaging units."
  }
}

variable "public_network_access_enabled" {
  description = "Whether the namespace is reachable over the public internet. Keep disabled and access it through a private endpoint - which requires the Premium SKU."
  type        = bool
  default     = false

  validation {
    condition     = var.public_network_access_enabled || var.sku == "Premium"
    error_message = "Disabled public network access requires the Premium SKU: Basic and Standard namespaces cannot use private endpoints, so they would have no usable endpoint at all."
  }
}

variable "queues" {
  description = "Queues to create in the namespace."
  type        = list(string)
  default     = []
}

variable "topics" {
  description = "Topics to create in the namespace. Requires the Standard or Premium SKU - the Basic tier supports queues only."
  type        = list(string)
  default     = []

  validation {
    condition     = var.sku != "Basic" || length(var.topics) == 0
    error_message = "Topics require the Standard or Premium SKU: the Basic tier supports queues only."
  }
}

variable "tags" {
  description = "Tags applied to the namespace."
  type        = map(string)
  default     = {}
}

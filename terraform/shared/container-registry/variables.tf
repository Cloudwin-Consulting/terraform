variable "name" {
  description = "The name of the container registry. Must be globally unique, 5-50 alphanumeric characters."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.name))
    error_message = "The registry name must be 5-50 alphanumeric characters."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the container registry is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the container registry is deployed."
  type        = string
}

variable "sku" {
  description = "The SKU of the container registry. Premium is required for private endpoints and disabled public network access."
  type        = string
  default     = "Premium"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be Basic, Standard or Premium."
  }

  validation {
    condition     = var.sku == "Premium" || var.public_network_access_enabled
    error_message = "Basic and Standard registries do not support disabled public network access or private endpoints; use the Premium SKU or enable public_network_access_enabled."
  }
}

variable "public_network_access_enabled" {
  description = "Whether the container registry is reachable over the public internet. Keep disabled and pull images through a private endpoint."
  type        = bool
  default     = false
}

variable "push_principal_ids" {
  description = "Principal IDs granted the AcrPush role to publish images from inside the network, e.g. a build agents group."
  type        = list(string)
  default     = []
}

variable "zone_redundancy_enabled" {
  description = "Whether the container registry is spread across availability zones. Requires the Premium SKU."
  type        = bool
  default     = false

  validation {
    condition     = !var.zone_redundancy_enabled || var.sku == "Premium"
    error_message = "zone_redundancy_enabled requires the Premium SKU: Basic and Standard registries do not support zone redundancy."
  }
}

variable "tags" {
  description = "Tags applied to the container registry."
  type        = map(string)
  default     = {}
}

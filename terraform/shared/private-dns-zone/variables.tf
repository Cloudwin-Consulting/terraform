variable "name" {
  description = "The name of the private DNS zone, e.g. privatelink.blob.core.windows.net or an internal service's hostname."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the zone is deployed."
  type        = string
}

variable "virtual_network_links" {
  description = "Virtual networks to link the zone to, keyed by a static link name (usually the virtual network name)."
  type = map(object({
    virtual_network_id   = string
    registration_enabled = optional(bool, false)
  }))
  default = {}
}

variable "a_records" {
  description = "A records to create in the zone, keyed by record name. Use @ for the zone apex and * for a wildcard."
  type = map(object({
    ttl     = optional(number, 300)
    records = list(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for name, record in var.a_records : length(record.records) > 0])
    error_message = "Each A record needs at least one IP address."
  }
}

variable "tags" {
  description = "Tags applied to the zone resources."
  type        = map(string)
  default     = {}
}

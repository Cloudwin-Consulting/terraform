variable "name" {
  description = "The name of the virtual network."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the virtual network is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the virtual network is deployed."
  type        = string
}

variable "address_space" {
  description = "The address space of the virtual network."
  type        = list(string)

  validation {
    condition     = length(var.address_space) > 0 && alltrue([for prefix in var.address_space : can(cidrhost(prefix, 0))])
    error_message = "address_space must contain at least one valid CIDR prefix."
  }
}

variable "dns_servers" {
  description = "Custom DNS servers for the virtual network. Leave empty to use Azure-provided DNS."
  type        = list(string)
  default     = []
}

variable "subnets" {
  description = "Map of subnets to create, keyed by subnet name."
  type = map(object({
    address_prefixes                              = list(string)
    service_endpoints                             = optional(list(string), [])
    private_endpoint_network_policies             = optional(string, "Enabled")
    private_link_service_network_policies_enabled = optional(bool, true)
    delegation = optional(object({
      name         = string
      service_name = string
      actions      = optional(list(string), ["Microsoft.Network/virtualNetworks/subnets/action"])
    }), null)
  }))
  default = {}

  validation {
    condition     = alltrue([for name, subnet in var.subnets : length(subnet.address_prefixes) > 0 && alltrue([for prefix in subnet.address_prefixes : can(cidrhost(prefix, 0))])])
    error_message = "Every subnet needs at least one valid CIDR prefix."
  }
}

variable "tags" {
  description = "Tags applied to the virtual network."
  type        = map(string)
  default     = {}
}

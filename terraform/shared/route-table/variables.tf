variable "name" {
  description = "The name of the route table."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the route table is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the route table is deployed."
  type        = string
}

variable "bgp_route_propagation_enabled" {
  description = "Whether routes learned by BGP (e.g. from a VPN gateway) propagate onto associated subnets."
  type        = bool
  default     = true
}

variable "routes" {
  description = "Routes in the route table. next_hop_in_ip_address is required when next_hop_type is VirtualAppliance, e.g. the firewall's private IP."
  type = list(object({
    name                   = string
    address_prefix         = string
    next_hop_type          = string
    next_hop_in_ip_address = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for route in var.routes : contains(["VirtualNetworkGateway", "VnetLocal", "Internet", "VirtualAppliance", "None"], route.next_hop_type) && (route.next_hop_type != "VirtualAppliance" || route.next_hop_in_ip_address != null)])
    error_message = "Routes need a valid next_hop_type, and VirtualAppliance routes need next_hop_in_ip_address."
  }
}

variable "subnet_associations" {
  description = "Subnets to associate with the route table. Keys are static identifiers, values are subnet IDs."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to the route table."
  type        = map(string)
  default     = {}
}

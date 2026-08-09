variable "name" {
  description = "The name of the DNS private resolver."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the resolver is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the resolver is deployed."
  type        = string
}

variable "virtual_network_id" {
  description = "The ID of the virtual network the resolver is attached to."
  type        = string
}

variable "inbound_subnet_id" {
  description = "The ID of the inbound endpoint subnet. Must be delegated to Microsoft.Network/dnsResolvers and at least a /28."
  type        = string
}

variable "tags" {
  description = "Tags applied to the resolver resources."
  type        = map(string)
  default     = {}
}

variable "hub_virtual_network" {
  description = "The hub virtual network to peer with. Its side of the peering is created through the azurerm.hub provider, which must be configured for the subscription this virtual network lives in."
  type = object({
    id                  = string
    name                = string
    resource_group_name = string
  })
}

variable "spoke_virtual_network" {
  description = "The spoke virtual network to peer with."
  type = object({
    id                  = string
    name                = string
    resource_group_name = string
  })
}

variable "allow_forwarded_traffic" {
  description = "Whether traffic forwarded by a network virtual appliance is allowed across the peering."
  type        = bool
  default     = true
}

variable "allow_gateway_transit" {
  description = "Whether the spoke may use a gateway in the hub. Enable once a VPN or ExpressRoute gateway exists in the hub."
  type        = bool
  default     = false
}

variable "use_remote_gateways" {
  description = "Whether the spoke routes on-premises traffic through the hub gateway. Requires allow_gateway_transit on the hub side."
  type        = bool
  default     = false
}

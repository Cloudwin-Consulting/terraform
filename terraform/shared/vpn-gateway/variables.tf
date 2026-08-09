variable "name" {
  description = "The name of the VPN gateway."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the VPN gateway is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the VPN gateway is deployed."
  type        = string
}

variable "subnet_id" {
  description = "The ID of the GatewaySubnet the VPN gateway is deployed into."
  type        = string
}

variable "sku" {
  description = "The SKU of the VPN gateway, e.g. VpnGw1 or VpnGw2. The legacy Basic SKU is not supported: it needs a Basic public IP, which is retired, while this module attaches a Standard one."
  type        = string
  default     = "VpnGw1"

  validation {
    condition     = can(regex("^VpnGw[1-5](AZ)?$", var.sku))
    error_message = "sku must be VpnGw1-VpnGw5, optionally with the AZ suffix. The legacy Basic SKU needs a retired Basic public IP and is not supported."
  }
}

variable "tags" {
  description = "Tags applied to the VPN gateway resources."
  type        = map(string)
  default     = {}
}

variable "zones" {
  description = "Availability zones of the deployment, e.g. [\"1\", \"2\", \"3\"] for zone redundancy. Requires an AZ gateway SKU, e.g. VpnGw1AZ. Leave null for a regional deployment."
  type        = list(string)
  default     = null

  validation {
    condition     = var.zones == null || can(regex("AZ$", var.sku))
    error_message = "zones requires an AZ gateway SKU, e.g. VpnGw1AZ: non-AZ SKUs cannot be zone deployed."
  }
}

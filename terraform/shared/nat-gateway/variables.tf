variable "name" {
  description = "The name of the NAT gateway."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the NAT gateway is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the NAT gateway is deployed."
  type        = string
}

variable "subnet_ids" {
  description = "IDs of the subnets whose outbound path the gateway takes over, keyed by a stable name."
  type        = map(string)
  default     = {}
}

variable "zone" {
  description = "The availability zone of the gateway and its public IP. NAT gateways are zonal: they occupy a single zone (or none) while serving machines in any zone. Leave null for a non-zonal deployment."
  type        = string
  default     = null

  validation {
    condition     = var.zone == null || contains(["1", "2", "3"], coalesce(var.zone, "1"))
    error_message = "zone must be 1, 2 or 3."
  }
}

variable "idle_timeout_in_minutes" {
  description = "Minutes an idle outbound flow is held before the gateway reclaims it."
  type        = number
  default     = 4

  validation {
    condition     = var.idle_timeout_in_minutes >= 4 && var.idle_timeout_in_minutes <= 120
    error_message = "idle_timeout_in_minutes must be between 4 and 120."
  }
}

variable "tags" {
  description = "Tags applied to the NAT gateway resources."
  type        = map(string)
  default     = {}
}

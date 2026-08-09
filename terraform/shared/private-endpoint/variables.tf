variable "name" {
  description = "The name of the private endpoint."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the private endpoint is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the private endpoint is deployed."
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet into which the private endpoint is deployed."
  type        = string
}

variable "private_connection_resource_id" {
  description = "The ID of the resource the private endpoint connects to."
  type        = string
}

variable "subresource_names" {
  description = "The subresource (group ID) the private endpoint connects to, e.g. [\"blob\"], [\"sites\"] or [\"azuremonitor\"]."
  type        = list(string)

  validation {
    condition     = length(var.subresource_names) == 1
    error_message = "Private endpoints connect to exactly one subresource (group ID)."
  }
}

variable "private_dns_zone_ids" {
  description = "Private DNS zone IDs to register the private endpoint with. Leave empty to skip DNS integration."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the private endpoint."
  type        = map(string)
  default     = {}
}

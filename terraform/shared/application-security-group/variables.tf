variable "name" {
  description = "The name of the application security group."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the application security group is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location of the application security group. Must match the region of the network interfaces that join it."
  type        = string
}

variable "tags" {
  description = "Tags applied to the application security group."
  type        = map(string)
  default     = {}
}

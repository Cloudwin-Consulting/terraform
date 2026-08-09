variable "name" {
  description = "The name of the user-assigned identity."
  type        = string

  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 128 && can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]*$", var.name))
    error_message = "The identity name must be 3-128 characters of letters, numbers, hyphens and underscores, starting alphanumeric."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the identity is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the identity is deployed."
  type        = string
}

variable "tags" {
  description = "Tags applied to the identity."
  type        = map(string)
  default     = {}
}

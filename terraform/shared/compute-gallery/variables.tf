variable "name" {
  description = "The name of the compute gallery. Alphanumerics, underscores and periods only."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9_.]{0,78}[a-zA-Z0-9])?$", var.name))
    error_message = "The gallery name must be up to 80 alphanumerics, underscores and periods, starting and ending alphanumeric."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the gallery is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the gallery is deployed."
  type        = string
}

variable "description" {
  description = "A description of the gallery."
  type        = string
  default     = null
}

variable "images" {
  description = "Image definitions to create in the gallery, keyed by image name."
  type = map(object({
    os_type                  = string
    publisher                = string
    offer                    = string
    sku                      = string
    hyper_v_generation       = optional(string, "V2")
    architecture             = optional(string, "x64")
    trusted_launch_supported = optional(bool, true)
  }))
  default = {}

  validation {
    condition     = alltrue([for name, image in var.images : contains(["Linux", "Windows"], image.os_type) && contains(["V1", "V2"], image.hyper_v_generation)])
    error_message = "Image os_type must be Linux or Windows and hyper_v_generation V1 or V2."
  }

  validation {
    condition     = alltrue([for name, image in var.images : image.hyper_v_generation == "V2" || !image.trusted_launch_supported])
    error_message = "Trusted launch requires generation V2 images: set trusted_launch_supported = false on V1 definitions."
  }
}

variable "tags" {
  description = "Tags applied to the gallery resources."
  type        = map(string)
  default     = {}
}

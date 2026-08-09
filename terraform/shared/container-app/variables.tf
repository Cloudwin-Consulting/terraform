variable "name" {
  description = "The name of the container app."
  type        = string

  validation {
    condition     = length(var.name) >= 2 && can(regex("^[a-z]([a-z0-9-]{0,30}[a-z0-9])?$", var.name))
    error_message = "The container app name must be 2-32 lowercase characters, start with a letter, end alphanumeric and contain only letters, numbers and hyphens."
  }
}

variable "container_app_environment_id" {
  description = "The ID of the container app environment the app runs in."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the container app is deployed."
  type        = string
}

variable "revision_mode" {
  description = "The revision mode of the container app, either Single or Multiple."
  type        = string
  default     = "Single"

  validation {
    condition     = contains(["Single", "Multiple"], var.revision_mode)
    error_message = "revision_mode must be Single or Multiple."
  }
}

variable "workload_profile_name" {
  description = "The name of the environment workload profile the app runs on."
  type        = string
  default     = "Consumption"
}

variable "identity_ids" {
  description = "User-assigned identity IDs attached alongside the system-assigned identity, e.g. for registry pulls."
  type        = list(string)
  default     = []
}

variable "registries" {
  description = "Container registries the app pulls images from with a user-assigned identity."
  type = list(object({
    server   = string
    identity = string
  }))
  default = []
}

variable "target_port" {
  description = "The port the container listens on for ingress traffic. Leave null to disable ingress."
  type        = number
  default     = null
}

variable "ingress_external_enabled" {
  description = "Whether ingress accepts traffic from outside the environment. On an internal environment this still only exposes the app on the environment's private load balancer."
  type        = bool
  default     = true
}

variable "container_name" {
  description = "The name of the container in the app's template. Defaults to the app name."
  type        = string
  default     = null
}

variable "image" {
  description = "The container image the app runs."
  type        = string
}

variable "cpu" {
  description = "The CPU cores allocated to the container."
  type        = number
  default     = 0.25
}

variable "memory" {
  description = "The memory allocated to the container."
  type        = string
  default     = "0.5Gi"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?Gi$", var.memory))
    error_message = "memory must be expressed in Gi, e.g. 0.5Gi."
  }
}

variable "min_replicas" {
  description = "The minimum number of replicas of the container app."
  type        = number
  default     = 1

  validation {
    condition     = var.min_replicas >= 0 && var.min_replicas <= 300
    error_message = "min_replicas must be between 0 and 300."
  }
}

variable "max_replicas" {
  description = "The maximum number of replicas of the container app."
  type        = number
  default     = 3

  validation {
    condition     = var.max_replicas >= var.min_replicas && var.max_replicas <= 300
    error_message = "max_replicas must be at least min_replicas and at most 300."
  }
}

variable "environment_variables" {
  description = "Environment variables set on the container. Use secrets and Key Vault references for sensitive values rather than plain environment variables."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to the container app."
  type        = map(string)
  default     = {}
}

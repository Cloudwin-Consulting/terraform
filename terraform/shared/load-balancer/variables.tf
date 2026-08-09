variable "name" {
  description = "The name of the load balancer."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the load balancer is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the load balancer is deployed."
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet the private frontend IP is allocated from. Required unless public_ip_enabled is set, where the frontend takes a public IP instead and this is ignored."
  type        = string
  default     = null

  validation {
    condition     = var.public_ip_enabled || var.subnet_id != null
    error_message = "subnet_id is required for a load balancer with a private frontend. Set public_ip_enabled for an internet-facing one instead."
  }
}

variable "rules" {
  description = "Load balancing rules, each with a health probe, all served from the load balancer's single frontend. probe_port defaults to the backend port; probe_request_path is required for Http/Https probes."
  type = list(object({
    name               = string
    protocol           = optional(string, "Tcp")
    frontend_port      = number
    backend_port       = number
    probe_protocol     = optional(string, "Tcp")
    probe_port         = optional(number)
    probe_request_path = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for rule in var.rules : contains(["Tcp", "Udp"], rule.protocol) && contains(["Tcp", "Http", "Https"], rule.probe_protocol) && (rule.probe_protocol == "Tcp" || rule.probe_request_path != null) && rule.frontend_port >= 1 && rule.frontend_port <= 65535 && rule.backend_port >= 1 && rule.backend_port <= 65535])
    error_message = "Rules need Tcp or Udp protocols, ports 1-65535, and Http/Https probes need a probe_request_path. HA-port (All) rules are not supported by this module."
  }
}

variable "public_ip_enabled" {
  description = "Whether the frontend takes a public IP, making the load balancer internet-facing, instead of a private address on subnet_id. Azure permits only one kind of frontend per load balancer, so this switches the frontend rather than adding to it."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the load balancer."
  type        = map(string)
  default     = {}
}

variable "zones" {
  description = "Availability zones of the frontend IP, e.g. [\"1\", \"2\", \"3\"] for zone redundancy. Leave null for a regional deployment."
  type        = list(string)
  default     = null
}

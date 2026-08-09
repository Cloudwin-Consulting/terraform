variable "name" {
  description = "The name of the Traffic Manager profile."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the profile is deployed."
  type        = string
}

variable "traffic_routing_method" {
  description = "How traffic is routed across endpoints: Priority, Weighted, Performance, Geographic, MultiValue or Subnet."
  type        = string
  default     = "Priority"

  validation {
    condition     = contains(["Priority", "Weighted", "Performance", "MultiValue"], var.traffic_routing_method)
    error_message = "traffic_routing_method must be Priority, Weighted, Performance or MultiValue: Geographic and Subnet routing need endpoint mappings this module does not model."
  }
}

variable "dns_relative_name" {
  description = "The globally unique relative DNS name of the profile, forming <name>.trafficmanager.net."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$", var.dns_relative_name))
    error_message = "dns_relative_name must contain only letters, numbers and hyphens, starting and ending alphanumeric."
  }
}

variable "dns_ttl" {
  description = "The TTL of the profile's DNS responses in seconds."
  type        = number
  default     = 60
}

variable "monitor_protocol" {
  description = "The protocol health probes use: HTTP, HTTPS or TCP."
  type        = string
  default     = "HTTPS"

  validation {
    condition     = contains(["HTTP", "HTTPS", "TCP"], var.monitor_protocol)
    error_message = "monitor_protocol must be HTTP, HTTPS or TCP."
  }
}

variable "monitor_port" {
  description = "The port health probes target."
  type        = number
  default     = 443
}

variable "monitor_path" {
  description = "The path health probes request. Ignored for TCP."
  type        = string
  default     = "/"
}

variable "external_endpoints" {
  description = "External endpoints of the profile. location is required for the Performance routing method; always_serve_enabled bypasses probing for privately reachable targets."
  type = list(object({
    name                 = string
    target               = string
    location             = optional(string)
    priority             = optional(number)
    weight               = optional(number)
    always_serve_enabled = optional(bool, false)
  }))
  default = []
}

variable "tags" {
  description = "Tags applied to the profile."
  type        = map(string)
  default     = {}
}

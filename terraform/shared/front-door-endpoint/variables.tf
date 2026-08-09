variable "name" {
  description = "The name of the endpoint. Must be globally unique as it forms the default hostname."
  type        = string

  validation {
    condition     = length(var.name) <= 46 && can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$", var.name))
    error_message = "The endpoint name must be up to 46 characters of letters, numbers and hyphens, starting and ending alphanumeric."
  }
}

variable "front_door_profile_id" {
  description = "The ID of the Front Door profile the endpoint is added to."
  type        = string
}

variable "origin_host_name" {
  description = "The hostname of the origin, e.g. a web app default hostname. An origin with no name of its own - a private link service publishing an internal load balancer - is named by its private address instead, which also requires certificate_name_check_enabled to be false."
  type        = string
}

variable "origin_http_port" {
  description = "The port the origin serves HTTP on."
  type        = number
  default     = 80
}

variable "origin_https_port" {
  description = "The port the origin serves HTTPS on."
  type        = number
  default     = 443
}

variable "origin_forwarding_protocol" {
  description = "How Front Door reaches the origin: HttpsOnly, HttpOnly, or MatchRequest. HttpOnly leaves the origin leg unencrypted - use it only for an origin that terminates no TLS and is reached over Private Link."
  type        = string
  default     = "HttpsOnly"

  validation {
    condition     = contains(["HttpsOnly", "HttpOnly", "MatchRequest"], var.origin_forwarding_protocol)
    error_message = "origin_forwarding_protocol must be HttpsOnly, HttpOnly or MatchRequest."
  }
}

variable "health_probe_path" {
  description = "The path probed to assess origin health."
  type        = string
  default     = "/"
}

variable "health_probe_protocol" {
  description = "The protocol the health probe uses: Http or Https. Must match what the origin serves."
  type        = string
  default     = "Https"

  validation {
    condition     = contains(["Http", "Https"], var.health_probe_protocol)
    error_message = "health_probe_protocol must be Http or Https."
  }
}

variable "certificate_name_check_enabled" {
  description = "Whether Front Door requires the origin's certificate to match origin_host_name. Must be false for an origin named by its address or reached over plain HTTP."
  type        = bool
  default     = true
}

variable "private_link" {
  description = "Connects the origin over Private Link (Premium SKU only). target_type is the origin's subresource, e.g. sites for a web app; leave it null when target_id is a private link service, which publishes a load balancer rather than a subresource. Leave the whole object null for a public origin."
  type = object({
    target_id   = string
    target_type = optional(string, null)
    location    = string
  })
  default = null
}

variable "tags" {
  description = "Tags applied to the endpoint."
  type        = map(string)
  default     = {}
}

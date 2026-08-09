variable "name" {
  description = "The name of the private link service."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the private link service is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the private link service is deployed. Must match the load balancer's."
  type        = string
}

variable "load_balancer_frontend_ip_configuration_ids" {
  description = "The frontend IP configuration IDs of the standard internal load balancer the service publishes."
  type        = list(string)

  validation {
    condition     = length(var.load_balancer_frontend_ip_configuration_ids) > 0
    error_message = "The service must publish at least one load balancer frontend IP configuration."
  }
}

variable "nat_subnet_id" {
  description = "The ID of the subnet the service draws its NAT addresses from. The subnet must have its private link service network policies disabled."
  type        = string
}

variable "nat_ip_count" {
  description = "How many NAT addresses the service takes from the subnet. More addresses allow more simultaneous connections."
  type        = number
  default     = 1

  validation {
    condition     = var.nat_ip_count >= 1 && var.nat_ip_count <= 8
    error_message = "nat_ip_count must be between 1 and 8."
  }
}

variable "visibility_subscription_ids" {
  description = "Subscriptions that may find the service by its alias. Leave empty to keep it private to its own subscription and to the Microsoft services granted access out of band, e.g. Front Door."
  type        = list(string)
  default     = []
}

variable "auto_approval_subscription_ids" {
  description = "Subscriptions whose private endpoint connections are approved without review. Leave empty to approve every connection by hand - visibility alone only lets a subscription ask."
  type        = list(string)
  default     = []

  validation {
    condition = length(var.auto_approval_subscription_ids) == 0 || contains(var.visibility_subscription_ids, "*") || alltrue([
      for subscription in var.auto_approval_subscription_ids :
      contains(var.visibility_subscription_ids, subscription)
    ])
    error_message = "Every subscription in auto_approval_subscription_ids must also be in visibility_subscription_ids: a subscription that cannot see the service never requests the connection its auto-approval would accept."
  }
}

variable "proxy_protocol_enabled" {
  description = "Whether the service prefixes connections with the TCP proxy protocol v2 header, which carries the consumer's address. The backend must understand it."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the private link service."
  type        = map(string)
  default     = {}
}

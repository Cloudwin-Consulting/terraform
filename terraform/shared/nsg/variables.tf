variable "name" {
  description = "The name of the network security group."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the network security group is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the network security group is deployed."
  type        = string
}

variable "security_rules" {
  description = "Security rules applied to the network security group. For each rule use exactly one of the singular or plural port attributes per side. Each side of a rule takes exactly one of an address prefix, address prefixes or application security group IDs."
  type = list(object({
    name                                       = string
    description                                = optional(string)
    priority                                   = number
    direction                                  = string
    access                                     = string
    protocol                                   = string
    source_port_range                          = optional(string)
    source_port_ranges                         = optional(list(string))
    destination_port_range                     = optional(string)
    destination_port_ranges                    = optional(list(string))
    source_address_prefix                      = optional(string)
    source_address_prefixes                    = optional(list(string))
    source_application_security_group_ids      = optional(list(string))
    destination_address_prefix                 = optional(string)
    destination_address_prefixes               = optional(list(string))
    destination_application_security_group_ids = optional(list(string))
  }))
  default = []

  validation {
    condition     = alltrue([for rule in var.security_rules : rule.priority >= 100 && rule.priority <= 4096 && contains(["Inbound", "Outbound"], rule.direction) && contains(["Allow", "Deny"], rule.access) && contains(["Tcp", "Udp", "Icmp", "Esp", "Ah", "*"], rule.protocol)])
    error_message = "Rules need a priority of 100-4096, a direction of Inbound or Outbound, an access of Allow or Deny and a valid protocol."
  }

  validation {
    condition     = alltrue([for rule in var.security_rules : length(rule.name) >= 1 && length(rule.name) <= 80 && length(rule.description == null ? "" : rule.description) <= 140])
    error_message = "Rule names are limited to 80 characters and rule descriptions to 140 characters."
  }

  validation {
    condition = alltrue([
      for rule in var.security_rules :
      (rule.source_port_range != null) != (rule.source_port_ranges != null) &&
      (rule.destination_port_range != null) != (rule.destination_port_ranges != null)
    ])
    error_message = "Each rule needs source and destination ports, in either the singular or plural form but not both."
  }

  validation {
    condition = alltrue([
      for rule in var.security_rules : alltrue([
        for value in [rule.source_port_range, rule.source_port_ranges, rule.destination_port_range, rule.destination_port_ranges, rule.source_address_prefix, rule.source_address_prefixes, rule.source_application_security_group_ids, rule.destination_address_prefix, rule.destination_address_prefixes, rule.destination_application_security_group_ids] :
        value == null ? true : length(value) > 0
      ])
    ])
    error_message = "The port, prefix and application security group attributes must not be empty strings or lists - omit unused attributes instead."
  }

  validation {
    condition = alltrue([
      for rule in var.security_rules :
      length([for value in [rule.source_address_prefix, rule.source_address_prefixes, rule.source_application_security_group_ids] : value if value != null]) == 1 &&
      length([for value in [rule.destination_address_prefix, rule.destination_address_prefixes, rule.destination_application_security_group_ids] : value if value != null]) == 1
    ])
    error_message = "Each side of a rule takes exactly one of an address prefix, address prefixes or application security group IDs."
  }

  validation {
    condition = alltrue([
      for direction in ["Inbound", "Outbound"] :
      length([for rule in var.security_rules : rule.priority if rule.direction == direction]) ==
      length(distinct([for rule in var.security_rules : rule.priority if rule.direction == direction]))
    ])
    error_message = "Rule priorities must be unique within each direction: Azure rejects two rules in the same direction with the same priority."
  }
}

variable "subnet_associations" {
  description = "Subnets to associate with the network security group. Keys are static identifiers, values are subnet IDs."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to the network security group."
  type        = map(string)
  default     = {}
}

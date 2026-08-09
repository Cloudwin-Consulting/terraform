variable "name" {
  description = "The name of the firewall policy."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the firewall policy is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the firewall policy is deployed."
  type        = string
}

variable "sku_tier" {
  description = "The SKU tier of the firewall policy. Must match the firewall it is attached to."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Basic, Standard or Premium."
  }
}

variable "threat_intelligence_mode" {
  description = "How the policy handles traffic that matches Microsoft's threat intelligence feed: Off, Alert or Deny. Deny blocks the high-confidence malicious IPs and domains the feed reports."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Off", "Alert", "Deny"], var.threat_intelligence_mode)
    error_message = "threat_intelligence_mode must be Off, Alert or Deny."
  }
}

variable "idps_mode" {
  description = "How intrusion detection and prevention (IDPS) treats matched traffic on Premium SKU policies: Off, Alert or Deny. Ignored on other SKUs, which do not support IDPS."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Off", "Alert", "Deny"], var.idps_mode)
    error_message = "idps_mode must be Off, Alert or Deny."
  }
}

variable "dns_proxy_enabled" {
  description = "Whether the firewall acts as a DNS proxy. Required for FQDN filtering in network rules."
  type        = bool
  default     = false
}

variable "dns_servers" {
  description = "Custom DNS servers the DNS proxy forwards to. Leave empty to use Azure DNS."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the firewall policy."
  type        = map(string)
  default     = {}
}

variable "rule_collection_groups" {
  description = "Rule collection groups to attach to the policy, keyed by group name. Each group can mix DNAT, network and application rule collections. Collection priorities must be unique within a group; network rules with destination_fqdns need dns_proxy_enabled; destination_urls, web_categories and terminate_tls need the Premium SKU."
  type = map(object({
    priority = number

    network_rule_collections = optional(list(object({
      name     = string
      priority = number
      action   = optional(string, "Allow")
      rules = list(object({
        name                  = string
        protocols             = list(string)
        source_addresses      = optional(list(string), [])
        source_ip_groups      = optional(list(string), [])
        destination_addresses = optional(list(string), [])
        destination_ip_groups = optional(list(string), [])
        destination_fqdns     = optional(list(string), [])
        destination_ports     = list(string)
      }))
    })), [])

    application_rule_collections = optional(list(object({
      name     = string
      priority = number
      action   = optional(string, "Allow")
      rules = list(object({
        name                  = string
        source_addresses      = optional(list(string), [])
        source_ip_groups      = optional(list(string), [])
        destination_fqdns     = optional(list(string), [])
        destination_fqdn_tags = optional(list(string), [])
        destination_urls      = optional(list(string), [])
        web_categories        = optional(list(string), [])
        terminate_tls         = optional(bool, false)
        protocols = optional(list(object({
          type = string
          port = number
        })), [{ type = "Https", port = 443 }])
      }))
    })), [])

    nat_rule_collections = optional(list(object({
      name     = string
      priority = number
      rules = list(object({
        name                = string
        protocols           = list(string)
        source_addresses    = optional(list(string), ["*"])
        destination_address = string
        destination_ports   = list(string)
        translated_address  = string
        translated_port     = number
      }))
    })), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for name, group in var.rule_collection_groups : group.priority >= 100 && group.priority <= 65000])
    error_message = "Rule collection group priorities must be between 100 and 65000."
  }

  validation {
    condition = alltrue([
      for name, group in var.rule_collection_groups : alltrue([
        for collection in concat(group.network_rule_collections, group.application_rule_collections, group.nat_rule_collections) :
        collection.priority >= 100 && collection.priority <= 65000
      ])
    ])
    error_message = "Rule collection priorities must be between 100 and 65000."
  }

  validation {
    condition = alltrue([
      for name, group in var.rule_collection_groups : alltrue([
        for collection in concat(group.network_rule_collections, group.application_rule_collections) :
        contains(["Allow", "Deny"], collection.action)
      ])
    ])
    error_message = "Network and application rule collection actions must be Allow or Deny."
  }

  validation {
    condition = alltrue([
      for name, group in var.rule_collection_groups :
      length(distinct(concat(
        [for collection in group.network_rule_collections : collection.priority],
        [for collection in group.application_rule_collections : collection.priority],
        [for collection in group.nat_rule_collections : collection.priority]
      ))) == length(group.network_rule_collections) + length(group.application_rule_collections) + length(group.nat_rule_collections)
    ])
    error_message = "Rule collection priorities must be unique within a group, across all collection types."
  }

  validation {
    condition = alltrue([
      for name, group in var.rule_collection_groups : alltrue([
        for collection in group.network_rule_collections : alltrue([
          for rule in collection.rules : alltrue([for protocol in rule.protocols : contains(["TCP", "UDP", "ICMP", "Any"], protocol)])
        ])
      ])
    ])
    error_message = "Network rule protocols must be TCP, UDP, ICMP or Any."
  }

  validation {
    condition = alltrue([
      for name, group in var.rule_collection_groups : alltrue([
        for collection in group.network_rule_collections : alltrue([
          for rule in collection.rules :
          length(concat(rule.destination_addresses, rule.destination_ip_groups, rule.destination_fqdns)) > 0
        ])
      ])
    ])
    error_message = "Every network rule needs at least one destination: addresses, IP groups or FQDNs."
  }

  validation {
    condition = alltrue([
      for name, group in var.rule_collection_groups : alltrue([
        for collection in group.application_rule_collections : alltrue([
          for rule in collection.rules :
          length(concat(rule.destination_fqdns, rule.destination_fqdn_tags, rule.destination_urls, rule.web_categories)) > 0
        ])
      ])
    ])
    error_message = "Every application rule needs at least one destination: FQDNs, FQDN tags, URLs or web categories."
  }

  validation {
    condition = var.sku_tier == "Premium" || alltrue([
      for name, group in var.rule_collection_groups : alltrue([
        for collection in group.application_rule_collections : alltrue([
          for rule in collection.rules : length(rule.destination_urls) == 0 && !rule.terminate_tls
        ])
      ])
    ])
    error_message = "destination_urls and terminate_tls require the Premium SKU."
  }

  validation {
    condition = alltrue([
      for name, group in var.rule_collection_groups : alltrue([
        for collection in group.nat_rule_collections : alltrue([
          for rule in collection.rules : alltrue([for protocol in rule.protocols : contains(["TCP", "UDP"], protocol)])
        ])
      ])
    ])
    error_message = "DNAT rule protocols must be TCP or UDP."
  }
}

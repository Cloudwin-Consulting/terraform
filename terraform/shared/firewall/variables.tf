variable "name" {
  description = "The name of the firewall."
  type        = string
}

variable "policy_name" {
  description = "The name of the firewall policy. Defaults to a name derived from the firewall name."
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "The resource group into which the firewall is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the firewall is deployed."
  type        = string
}

variable "subnet_id" {
  description = "The ID of the AzureFirewallSubnet the firewall is deployed into."
  type        = string
}

variable "sku_tier" {
  description = "The SKU tier of the firewall: Standard or Premium. Basic is not supported as it needs a management subnet and IP configuration this module does not provision."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Standard or Premium."
  }
}

variable "threat_intelligence_mode" {
  description = "How the firewall handles traffic that matches Microsoft's threat intelligence feed: Off, Alert or Deny. Deny blocks the high-confidence malicious IPs and domains the feed reports."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Off", "Alert", "Deny"], var.threat_intelligence_mode)
    error_message = "threat_intelligence_mode must be Off, Alert or Deny."
  }
}

variable "idps_mode" {
  description = "How intrusion detection and prevention (IDPS) treats matched traffic when sku_tier is Premium: Off, Alert or Deny. Ignored on the Standard SKU, which does not support IDPS."
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

variable "log_analytics_workspace_id" {
  description = "The ID of a Log Analytics workspace to send diagnostics to. Leave null to skip diagnostics."
  type        = string
  default     = null
}

variable "enable_diagnostics" {
  description = "Whether to create the diagnostic setting. Defaults to creating it when log_analytics_workspace_id is set. Set explicitly when the workspace is created in the same apply: its ID is unknown at plan time, so it cannot decide whether the setting exists."
  type        = bool
  default     = null

  validation {
    condition     = var.enable_diagnostics != true || var.log_analytics_workspace_id != null
    error_message = "enable_diagnostics requires log_analytics_workspace_id to be set."
  }
}

variable "tags" {
  description = "Tags applied to the firewall resources."
  type        = map(string)
  default     = {}
}

variable "zones" {
  description = "Availability zones of the deployment, e.g. [\"1\", \"2\", \"3\"] for zone redundancy. Leave null for a regional deployment."
  type        = list(string)
  default     = null
}

variable "rule_collection_groups" {
  description = "Rule collection groups attached to the firewall's policy, keyed by group name. Each group can mix DNAT, network and application rule collections; see the firewall-policy sub-module for full field semantics. DNAT rules may leave destination_address null to target the firewall's own public IP."
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
        destination_address = optional(string)
        destination_ports   = list(string)
        translated_address  = string
        translated_port     = number
      }))
    })), [])
  }))
  default = {}
}

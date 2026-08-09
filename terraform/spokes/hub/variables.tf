variable "deployment_subscription_id" {
  description = "The Azure subscription into which resources will be deployed."
  type        = string
}

variable "deployment_location" {
  description = "The Azure location into which resources will be deployed."
  type        = string
}

variable "deployment_name" {
  description = "The name of the workload being deployed, without the environment (e.g. hub-spoke). Every resource name is derived from it and environment together - rg-<deployment_name>-<environment> for the core resource group, rg-<deployment_name>-<environment>-network, -dns and -secrets for the network, DNS and secrets groups, and <abbreviation>-<deployment_name>-<environment> for the resources in them - so the pair must be unique across all stacks and environments: a workload name reused in the same environment derives the same resource group name and clashes on globally unique names. Downstream stacks rebuild this spoke's names the same way, so their hub_deployment_name must match this value and they must deploy into the same environment."
  type        = string
}

variable "environment" {
  description = "The environment this deployment targets (e.g. rd, dev, qa, prod). It is appended to deployment_name to derive every resource name, so a single configuration targets any environment by changing this value alone."
  type        = string
}

variable "enable_virtual_network" {
  description = "Whether to deploy the hub virtual network and its network security group. Every other component requires it."
  type        = bool
  default     = true
}

variable "address_space" {
  description = "The address space of the hub virtual network."
  type        = list(string)
  default     = ["10.240.0.0/22"]
}

variable "gateway_subnet_prefix" {
  description = "The address prefix reserved for a VPN or ExpressRoute gateway."
  type        = string
  default     = "10.240.0.0/27"
}

variable "dns_resolver_inbound_subnet_prefix" {
  description = "The address prefix of the DNS resolver inbound endpoint subnet, created only when the resolver is enabled."
  type        = string
  default     = "10.240.0.32/28"
}

variable "firewall_subnet_prefix" {
  description = "The address prefix reserved for Azure Firewall."
  type        = string
  default     = "10.240.0.64/26"
}

variable "bastion_subnet_prefix" {
  description = "The address prefix of the Azure Bastion subnet."
  type        = string
  default     = "10.240.0.128/26"
}

variable "shared_subnet_prefix" {
  description = "The address prefix of the shared services subnet."
  type        = string
  default     = "10.240.1.0/24"
}

variable "enable_bastion" {
  description = "Whether to deploy Azure Bastion into the hub."
  type        = bool
  default     = false
}

variable "bastion_sku" {
  description = "The SKU of the Azure Bastion host: Developer, Basic, Standard or Premium. The free Developer SKU attaches directly to the virtual network and must not have an IP configuration; every other SKU deploys into AzureBastionSubnet with its own public IP."
  type        = string
  default     = "Developer"

  validation {
    condition     = contains(["Developer", "Basic", "Standard", "Premium"], var.bastion_sku)
    error_message = "bastion_sku must be Developer, Basic, Standard or Premium."
  }
}

variable "enable_private_dns_zones" {
  description = "Whether to create the private DNS zones used by private endpoints. Required by every stack that deploys a private endpoint."
  type        = bool
  default     = false
}

variable "private_dns_zone_names" {
  description = "Private DNS zones created in the hub for private endpoint name resolution."
  type        = list(string)
  default = [
    "privatelink.azurewebsites.net",
    "privatelink.blob.core.windows.net",
    "privatelink.file.core.windows.net",
    "privatelink.queue.core.windows.net",
    "privatelink.table.core.windows.net",
    "privatelink.vaultcore.azure.net",
    "privatelink.azurecr.io",
    "privatelink.servicebus.windows.net",
    "privatelink.database.windows.net",
    "privatelink.postgres.database.azure.com",
    "privatelink.mysql.database.azure.com",
    "privatelink.redis.cache.windows.net",
    "privatelink.azconfig.io",
    "privatelink.documents.azure.com",
    "privatelink.monitor.azure.com",
    "privatelink.oms.opinsights.azure.com",
    "privatelink.ods.opinsights.azure.com",
    "privatelink.agentsvc.azure-automation.net",
  ]
}

variable "additional_private_dns_zone_names" {
  description = "Extra private DNS zones created in the hub alongside the defaults, e.g. the geo-specific privatelink.<geo>.backup.windowsazure.com zone that Recovery Services vault private endpoints resolve through."
  type        = list(string)
  default     = []
}

variable "enable_firewall" {
  description = "Whether to deploy Azure Firewall into the reserved AzureFirewallSubnet."
  type        = bool
  default     = false
}

variable "firewall_sku_tier" {
  description = "The SKU tier of the firewall: Standard or Premium."
  type        = string
  default     = "Standard"
}

variable "firewall_threat_intelligence_mode" {
  description = "How the firewall policy handles traffic that matches Microsoft's threat intelligence feed: Off, Alert or Deny. Deny blocks the high-confidence malicious IPs and domains the feed reports."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Off", "Alert", "Deny"], var.firewall_threat_intelligence_mode)
    error_message = "firewall_threat_intelligence_mode must be Off, Alert or Deny."
  }
}

variable "firewall_idps_mode" {
  description = "How intrusion detection and prevention (IDPS) treats matched traffic when firewall_sku_tier is Premium: Off, Alert or Deny. Ignored on the Standard SKU, which does not support IDPS."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Off", "Alert", "Deny"], var.firewall_idps_mode)
    error_message = "firewall_idps_mode must be Off, Alert or Deny."
  }
}

variable "firewall_dns_proxy_enabled" {
  description = "Whether the firewall acts as a DNS proxy. Required when any firewall network rule filters on destination_fqdns."
  type        = bool
  default     = false

  validation {
    condition = var.firewall_dns_proxy_enabled || alltrue([
      for name, group in var.firewall_rule_collection_groups : alltrue([
        for collection in group.network_rule_collections : alltrue([
          for rule in collection.rules : length(rule.destination_fqdns) == 0
        ])
      ])
    ])
    error_message = "Network rules with destination_fqdns require firewall_dns_proxy_enabled: FQDN filtering only works when the firewall proxies DNS."
  }
}

variable "firewall_dns_servers" {
  description = "Custom DNS servers the firewall's DNS proxy forwards to, e.g. domain controllers. Leave empty to use Azure DNS."
  type        = list(string)
  default     = []
}

variable "firewall_zones" {
  description = "Availability zones of the firewall, e.g. [\"1\", \"2\", \"3\"] for zone redundancy. Leave null for a regional deployment."
  type        = list(string)
  default     = null
}

variable "firewall_rule_collection_groups" {
  description = "Rule collection groups attached to the firewall policy when the firewall is enabled. The default is a worked baseline for this topology: outbound network rules for platform dependencies, outbound application rules for OS updates and source control, and an inbound DNAT rule publishing the application gateway's private frontend through the firewall's public IP (adjust translated_address to the gateway's actual frontend IP, or remove the collection if nothing is published). The DNAT rule's translated_address must equal the application spoke's application_gateway_private_ip_address output. The hub deploys before the spoke, so nothing checks this at plan time - the two addresses drift silently, and the published entry point then resolves to an address nothing listens on."
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

  default = {
    platform-baseline = {
      priority = 300

      # DNAT first: publish the application gateway's private frontend
      # on the firewall's public IP (destination_address null = the
      # firewall's own public IP).
      nat_rule_collections = [
        {
          name     = "inbound-dnat"
          priority = 100
          rules = [
            # The worked application gateway listens on HTTP 80 (the
            # spoke passes it no TLS certificate); publish that
            # listener as-is, and switch this rule to 443 once the
            # gateway terminates TLS with a key vault certificate.
            {
              name               = "http-to-app-gateway"
              protocols          = ["TCP"]
              source_addresses   = ["*"]
              destination_ports  = ["80"]
              translated_address = "10.240.7.42"
              translated_port    = 80
            }
          ]
        }
      ]

      # Outbound network rules for the platform dependencies every
      # spoke workload needs.
      network_rule_collections = [
        {
          name     = "allow-outbound-platform"
          priority = 200
          action   = "Allow"
          rules = [
            {
              name                  = "dns-to-azure"
              protocols             = ["TCP", "UDP"]
              source_addresses      = ["10.240.0.0/16"]
              destination_addresses = ["168.63.129.16"]
              destination_ports     = ["53"]
            },
            {
              name                  = "ntp"
              protocols             = ["UDP"]
              source_addresses      = ["10.240.0.0/16"]
              destination_addresses = ["*"]
              destination_ports     = ["123"]
            },
            {
              name                  = "entra-id"
              protocols             = ["TCP"]
              source_addresses      = ["10.240.0.0/16"]
              destination_addresses = ["AzureActiveDirectory"]
              destination_ports     = ["443"]
            },
            {
              name                  = "azure-monitor"
              protocols             = ["TCP"]
              source_addresses      = ["10.240.0.0/16"]
              destination_addresses = ["AzureMonitor"]
              destination_ports     = ["443"]
            }
          ]
        }
      ]

      # Outbound application rules for OS updates and source control.
      application_rule_collections = [
        {
          name     = "allow-outbound-web"
          priority = 400
          action   = "Allow"
          rules = [
            {
              name                  = "windows-update"
              source_addresses      = ["10.240.0.0/16"]
              destination_fqdn_tags = ["WindowsUpdate"]
              protocols = [
                { type = "Http", port = 80 },
                { type = "Https", port = 443 }
              ]
            },
            {
              name             = "ubuntu-packages"
              source_addresses = ["10.240.0.0/16"]
              destination_fqdns = [
                "archive.ubuntu.com",
                "security.ubuntu.com",
                "azure.archive.ubuntu.com"
              ]
              protocols = [
                { type = "Http", port = 80 },
                { type = "Https", port = 443 }
              ]
            },
            {
              name             = "github"
              source_addresses = ["10.240.0.0/16"]
              destination_fqdns = [
                "github.com",
                "*.github.com",
                "*.githubusercontent.com"
              ]
              protocols = [
                { type = "Https", port = 443 }
              ]
            }
          ]
        }
      ]
    }
  }
}

variable "enable_dns_resolver" {
  description = "Whether to deploy the Azure DNS Private Resolver and its delegated inbound subnet."
  type        = bool
  default     = false
}

variable "enable_vpn_gateway" {
  description = "Whether to deploy a VPN gateway into the reserved GatewaySubnet. Deployment takes 30 minutes or more."
  type        = bool
  default     = false
}

variable "vpn_gateway_sku" {
  description = "The SKU of the VPN gateway, e.g. VpnGw1 or VpnGw2."
  type        = string
  default     = "VpnGw1"
}

variable "enable_platform_key_vault" {
  description = "Whether to deploy the hub's platform key vault into the spoke's secrets resource group (rg-<deployment_name>-<environment>-secrets), for secrets that platform deployments consume. Requires enable_virtual_network and enable_private_dns_zones."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_platform_key_vault || var.enable_virtual_network
    error_message = "enable_platform_key_vault requires enable_virtual_network: the vault is only reachable through its private endpoint."
  }

  validation {
    condition     = !var.enable_platform_key_vault || var.enable_private_dns_zones
    error_message = "enable_platform_key_vault requires enable_private_dns_zones: without the vault's private DNS zone its hostname does not resolve to the private endpoint, leaving the vault unreachable."
  }
}

variable "platform_key_vault_name" {
  description = "The globally unique name of the platform key vault. Defaults to kv-<deployment_name>-<environment>, which must stay within the 24 character vault name limit; it deploys into the dedicated rg-<deployment_name>-<environment>-secrets resource group."
  type        = string
  default     = null
}

variable "platform_key_vault_secrets_officer_principal_ids" {
  description = "Principal IDs granted the Key Vault Secrets Officer role on the platform key vault to pre-load secrets from inside the network, e.g. an administrators group object ID."
  type        = list(string)
  default     = []
}

variable "vpn_gateway_zones" {
  description = "Availability zones of the VPN gateway's public IP, e.g. [\"1\", \"2\", \"3\"]. Requires an AZ gateway SKU, e.g. VpnGw1AZ."
  type        = list(string)
  default     = null
}

variable "enable_monitor_alerts" {
  description = "Whether to deploy the Azure Monitor action group with subscription service and resource health alerts. Requires at least one receiver in monitor_alert_email_receivers, so incidents actually reach someone."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_monitor_alerts || length(var.monitor_alert_email_receivers) > 0
    error_message = "enable_monitor_alerts requires at least one monitor_alert_email_receivers entry: an action group without receivers records incidents but never delivers them."
  }
}

variable "monitor_action_group_short_name" {
  description = "The short name of the action group shown in notifications, at most 12 characters."
  type        = string
  default     = "hub-ops"
}

variable "monitor_alert_email_receivers" {
  description = "Email receivers of the action group, keyed by receiver name."
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------
# Standard tags
#
# Every taggable resource this stack deploys carries the mandatory
# tag set - Application, Environment, Owner, CostCenter, ManagedBy
# and Criticality - plus the standard tags that apply to it. They are
# built once into local.common_tags and passed to every resource and
# every shared module, so tagging is configured here rather than
# resource by resource. The optional tags are only added once they
# have a value, so nothing carries an empty tag.
# ------------------------------------------------------------

variable "application" {
  description = "The value of the Application tag: the application or workload the resources belong to. Defaults to deployment_name."
  type        = string
  default     = null

  validation {
    condition     = var.application == null ? true : trimspace(var.application) != ""
    error_message = "application must not be empty. Leave it null to derive the Application tag from deployment_name."
  }
}

variable "environment_tag" {
  description = "The value of the Environment tag. Defaults to the standard name of the environment this stack deploys into (rd -> RD, dev -> Development, qa -> QA, prod -> Production); set it explicitly when environment holds a name outside that set. It is deliberately separate from environment, which stays the short form every resource name is derived from."
  type        = string
  default     = null

  validation {
    condition     = var.environment_tag == null ? true : contains(["RD", "Development", "QA", "Production"], var.environment_tag)
    error_message = "environment_tag must be one of: RD, Development, QA, Production."
  }

  validation {
    condition     = var.environment_tag != null || contains(["rd", "dev", "qa", "prod"], lower(var.environment))
    error_message = "environment_tag must be set explicitly when environment is not one of rd, dev, qa or prod."
  }
}

variable "owner" {
  description = "The value of the Owner tag: the team accountable for the workload."
  type        = string
  default     = "PlatformEngineering"

  validation {
    condition     = trimspace(var.owner) != ""
    error_message = "owner must not be empty: every resource carries an Owner tag."
  }
}

variable "cost_center" {
  description = "The value of the CostCenter tag: the cost centre this deployment's Azure spend is charged to. Defaults to the Application tag's value."
  type        = string
  default     = null

  validation {
    condition     = var.cost_center == null ? true : trimspace(var.cost_center) != ""
    error_message = "cost_center must not be empty. Leave it null to charge the spend to the Application tag's value."
  }
}

variable "criticality" {
  description = "The value of the Criticality tag: how business critical this deployment is."
  type        = string
  default     = "Medium"

  validation {
    condition     = contains(["Critical", "High", "Medium", "Low"], var.criticality)
    error_message = "criticality must be one of: Critical, High, Medium, Low."
  }
}

variable "service" {
  description = "The value of the Service tag: the service this deployment provides. One of Networking, Monitoring, ApplicationPlatform, Integration, Data, Compute, Management, EndUserComputing or EntryPoint."
  type        = string
  default     = "Networking"

  validation {
    condition     = contains(["Networking", "Monitoring", "ApplicationPlatform", "Integration", "Data", "Compute", "Management", "EndUserComputing", "EntryPoint"], var.service)
    error_message = "service must be one of: Networking, Monitoring, ApplicationPlatform, Integration, Data, Compute, Management, EndUserComputing, EntryPoint."
  }
}

variable "data_classification" {
  description = "The value of the DataClassification tag: the most sensitive data this deployment holds."
  type        = string
  default     = "Internal"

  validation {
    condition     = contains(["Public", "Internal", "Confidential", "Restricted"], var.data_classification)
    error_message = "data_classification must be one of: Public, Internal, Confidential, Restricted."
  }
}

variable "lifecycle_stage" {
  description = "The value of the Lifecycle tag: how long this deployment is expected to live. Named lifecycle_stage because Terraform reserves lifecycle as a variable name."
  type        = string
  default     = "Permanent"

  validation {
    condition     = contains(["Permanent", "Temporary", "Sandbox"], var.lifecycle_stage)
    error_message = "lifecycle_stage must be one of: Permanent, Temporary, Sandbox."
  }
}

variable "expiry_date" {
  description = "The value of the optional ExpiryDate tag, as YYYY-MM-DD: the date after which this deployment may be removed. Leave null on deployments that do not expire - the tag is then not applied at all rather than applied empty."
  type        = string
  default     = null

  validation {
    condition     = var.expiry_date == null ? true : can(formatdate("YYYY-MM-DD", "${var.expiry_date}T00:00:00Z"))
    error_message = "expiry_date must be a real calendar date in YYYY-MM-DD form, or null on deployments that do not expire."
  }
}

variable "business_unit" {
  description = "The value of the optional BusinessUnit tag: the part of the organisation the workload belongs to. Leave null to leave the tag off rather than applying it empty."
  type        = string
  default     = null

  validation {
    condition     = var.business_unit == null ? true : trimspace(var.business_unit) != ""
    error_message = "business_unit must not be empty. Leave it null to leave the BusinessUnit tag off."
  }
}

variable "repository" {
  description = "The value of the optional Repository tag: the source repository this deployment is applied from. Leave null to leave the tag off rather than applying it empty."
  type        = string
  default     = null

  validation {
    condition     = var.repository == null ? true : trimspace(var.repository) != ""
    error_message = "repository must not be empty. Leave it null to leave the Repository tag off."
  }
}

variable "tags" {
  description = "Additional tags applied to all resources in the deployment, merged over the standard tags."
  type        = map(string)
  default     = {}
}

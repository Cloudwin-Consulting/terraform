variable "deployment_subscription_id" {
  description = "The Azure subscription into which resources will be deployed."
  type        = string
}

variable "deployment_location" {
  description = "The Azure location into which resources will be deployed."
  type        = string
}

variable "deployment_name" {
  description = "The name of the workload being deployed, without the environment (e.g. monitoring-spoke). Every resource name is derived from it and environment together - rg-<deployment_name>-<environment> for the core resource group, rg-<deployment_name>-<environment>-network, -dns and -secrets for the network, DNS and secrets groups, and <abbreviation>-<deployment_name>-<environment> for the resources in them - so the pair must be unique across all stacks and environments: a workload name reused in the same environment derives the same resource group name and clashes on globally unique names. Downstream stacks rebuild this spoke's names the same way, so their monitoring_deployment_name must match this value and they must deploy into the same environment."
  type        = string
}

variable "environment" {
  description = "The environment this deployment targets (e.g. rd, dev, qa, prod). It is appended to deployment_name to derive every resource name, and to the upstream workload names this stack looks its dependencies up by, so a single configuration targets any environment by changing this value alone."
  type        = string
}

variable "enable_virtual_network" {
  description = "Whether to deploy the monitoring spoke virtual network and its network security group. The private endpoints require it."
  type        = bool
  default     = true
}

variable "address_space" {
  description = "The address space of the monitoring spoke virtual network."
  type        = list(string)
  default     = ["10.240.8.0/22"]
}

variable "private_endpoint_subnet_name" {
  description = "The name of the subnet that hosts private endpoints. Must be a key of the subnets variable."
  type        = string
  default     = "snet-private-endpoints"
}

variable "private_endpoint_subnet_prefix" {
  description = "The address prefix of the private endpoint subnet."
  type        = string
  default     = "10.240.8.0/24"
}

variable "enable_hub_peering" {
  description = "Whether to peer the spoke with the hub virtual network."
  type        = bool
  default     = false
}

variable "use_hub_gateway" {
  description = "Whether spoke traffic can use the hub's VPN or ExpressRoute gateway through the peering. Requires the hub gateway to be deployed first."
  type        = bool
  default     = false
}

variable "enable_hub_dns_zone_links" {
  description = "Whether to link the spoke to the hub's private DNS zones. Requires the hub to have its private DNS zones enabled."
  type        = bool
  default     = false
}

variable "enable_application_spoke_peering" {
  description = "Whether to peer the monitoring spoke directly with the application spoke. Hub peering is not transitive, so application spoke workloads need this (or a routed path through a hub firewall) to reach the private ingestion endpoint. Deploy the application spoke first."
  type        = bool
  default     = false
}

variable "application_spoke_subscription_id" {
  description = "The Azure subscription the application spoke is deployed into, when it differs from this deployment's subscription. Leave null when the spokes share a subscription. The deployment identity must be able to read the application spoke's virtual network and create its side of the peering there."
  type        = string
  default     = null
}

variable "application_spoke_deployment_name" {
  description = "The workload name of the application spoke this spoke peers with, without the environment (e.g. app-spoke). Its network resource group and virtual network are looked up as rg-<application_spoke_deployment_name>-<environment>-network and vnet-<application_spoke_deployment_name>-<environment>, so it must match the spoke stack's deployment_name and the spoke must be deployed into the same environment. Only used when enable_application_spoke_peering is true."
  type        = string
  default     = "app-spoke"
}

variable "hub_subscription_id" {
  description = "The Azure subscription the hub is deployed into, when it differs from this deployment's subscription. Leave null when hub and spoke share a subscription. The deployment identity must be able to read the hub's virtual network and private DNS zones and to create peerings and DNS zone links there."
  type        = string
  default     = null
}

variable "hub_deployment_name" {
  description = "The workload name of the hub this stack looks up, without the environment (e.g. hub-spoke). Its network and DNS resource groups are looked up as rg-<hub_deployment_name>-<environment>-network and rg-<hub_deployment_name>-<environment>-dns, and its virtual network as vnet-<hub_deployment_name>-<environment>, so it must match the hub stack's deployment_name and the hub must be deployed into the same environment."
  type        = string
  default     = "hub-spoke"
}

variable "hub_private_dns_zone_names" {
  description = "Private DNS zones in the hub to link this spoke to."
  type        = list(string)
  default = [
    "privatelink.azurewebsites.net",
    "privatelink.blob.core.windows.net",
    "privatelink.monitor.azure.com",
    "privatelink.oms.opinsights.azure.com",
    "privatelink.ods.opinsights.azure.com",
    "privatelink.agentsvc.azure-automation.net",
  ]
}

variable "enable_log_analytics" {
  description = "Whether to deploy the Log Analytics workspace, the Azure Monitor Private Link Scope and its private endpoint. Required by the application stacks' diagnostics. Requires enable_virtual_network, since ingestion is private only."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_log_analytics || var.enable_virtual_network
    error_message = "enable_log_analytics requires enable_virtual_network: ingestion is private only and needs the private endpoint subnet."
  }
}

variable "ampls_private_dns_zone_names" {
  description = "Private DNS zones in the hub used by the Azure Monitor Private Link Scope endpoint."
  type        = list(string)
  default = [
    "privatelink.monitor.azure.com",
    "privatelink.oms.opinsights.azure.com",
    "privatelink.ods.opinsights.azure.com",
    "privatelink.agentsvc.azure-automation.net",
    "privatelink.blob.core.windows.net",
  ]
}

variable "log_retention_in_days" {
  description = "The number of days data is retained in the Log Analytics workspace."
  type        = number
  default     = 30
}

variable "enable_application_insights" {
  description = "Whether to deploy an Application Insights component stored in the workspace. Requires enable_log_analytics."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_application_insights || var.enable_log_analytics
    error_message = "enable_application_insights requires enable_log_analytics."
  }
}

variable "enable_log_archive_storage" {
  description = "Whether to deploy the log archive storage account, its private endpoint and the workspace data export rule that fills it. Requires enable_virtual_network and enable_log_analytics."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_log_archive_storage || var.enable_virtual_network
    error_message = "enable_log_archive_storage requires enable_virtual_network: readers reach the account through its private endpoint, which needs the private endpoint subnet."
  }

  validation {
    condition     = !var.enable_log_archive_storage || var.enable_log_analytics
    error_message = "enable_log_archive_storage requires enable_log_analytics: the workspace's data export rule is what writes logs into the archive account."
  }
}

variable "storage_account_name" {
  description = "The name of the log archive storage account. Defaults to st<deployment_name>-<environment> stripped of hyphens, which must stay within the 24 character storage account name limit."
  type        = string
  default     = null
}

variable "log_archive_replication_type" {
  description = "The replication type of the log archive storage account. Geo-zone-redundant by default: the archive holds long-term retention data, and cross-region replication (GRS, GZRS) is the recommended redundancy for data export destinations."
  type        = string
  default     = "GZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.log_archive_replication_type)
    error_message = "log_archive_replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS."
  }
}

variable "log_archive_public_network_access_enabled" {
  description = "Whether the log archive storage account keeps its public endpoint reachable. The workspace's data export rule delivers as a trusted Microsoft service through the public endpoint, so the compliant default of private-only access blocks export delivery; enable this if exported logs must keep flowing (the account's network rules still deny everything except the trusted bypass)."
  type        = bool
  default     = false
}

variable "log_archive_shared_access_key_enabled" {
  description = "Whether shared key authorisation is allowed on the log archive storage account. The workspace's data export rule authorises its writes with shared-key access - it has no managed identity - so the compliant default blocks export delivery; enable this if exported logs must keep flowing."
  type        = bool
  default     = false
}

variable "log_archive_customer_managed_key" {
  description = "Encrypts the log archive storage account with a customer-managed key instead of Microsoft-managed keys. Pre-create the key from inside the network in a vault with purge protection enabled and reference it here. The vault must keep public network access enabled with default-deny network rules: Azure Storage wraps and unwraps the key as a trusted service through the vault's public endpoint, and the trusted-services bypass does not apply to a vault whose public endpoint is disabled - a vault deployed with the key-vault module's defaults (like this spoke's platform key vault) is therefore not reachable for this purpose. Leave null for Microsoft-managed keys."
  type = object({
    key_vault_id = string
    key_name     = string
    key_version  = optional(string)
  })
  default = null
}

variable "log_archive_table_names" {
  description = "The workspace tables the data export rule continuously writes into the archive storage account."
  type        = list(string)
  default     = ["AzureActivity", "Heartbeat", "Perf", "Syslog", "Event"]

  validation {
    condition     = length(var.log_archive_table_names) > 0
    error_message = "log_archive_table_names needs at least one table for the export rule to write."
  }
}

variable "enable_platform_key_vault" {
  description = "Whether to deploy the spoke's platform key vault into the spoke's secrets resource group (rg-<deployment_name>-<environment>-secrets), for secrets that monitoring deployments consume. Requires enable_virtual_network and the hub's private DNS zones."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_platform_key_vault || var.enable_virtual_network
    error_message = "enable_platform_key_vault requires enable_virtual_network: the vault is only reachable through its private endpoint."
  }

  validation {
    condition     = !var.enable_platform_key_vault || var.enable_hub_dns_zone_links
    error_message = "enable_platform_key_vault requires enable_hub_dns_zone_links: without the vault zone linked to this spoke's network, the vault hostname does not resolve to its private endpoint."
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
  default     = "Monitoring"

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

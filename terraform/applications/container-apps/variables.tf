variable "deployment_subscription_id" {
  description = "The Azure subscription into which resources will be deployed."
  type        = string
}

variable "deployment_location" {
  description = "The Azure location into which resources will be deployed."
  type        = string
}

variable "deployment_name" {
  description = "The name of the workload being deployed, without the environment (e.g. app1). Every resource name is derived from it and environment together - rg-<deployment_name>-<environment> for the resource group, <abbreviation>-<deployment_name>-<environment> for the resources in it - so the pair must be unique across all stacks and environments: a workload name reused in the same environment derives the same resource group name and clashes on globally unique names."
  type        = string
}

variable "environment" {
  description = "The environment this deployment targets (e.g. rd, dev, qa, prod). It is appended to deployment_name to derive every resource name, and to the upstream workload names this stack looks its dependencies up by, so a single configuration targets any environment by changing this value alone."
  type        = string
}

variable "app_spoke_subscription_id" {
  description = "The Azure subscription the application spoke is deployed into, when it differs from this deployment's subscription. Leave null when they share a subscription. This stack's spoke lookups run against it, and the deployment identity needs read access to the referenced spoke resources there."
  type        = string
  default     = null
}

variable "app_spoke_deployment_name" {
  description = "The workload name of the application spoke this stack deploys into, without the environment (e.g. app-spoke). Its network resource group and virtual network are looked up as rg-<app_spoke_deployment_name>-<environment>-network and vnet-<app_spoke_deployment_name>-<environment>, so it must match the spoke stack's deployment_name and the spoke must be deployed into the same environment. A name that does not match fails this stack's lookups at plan time."
  type        = string
  default     = "app-spoke"
}

variable "container_apps_subnet_name" {
  description = "The name of the application spoke's delegated container apps infrastructure subnet. Must match a key of the spoke's subnets variable."
  type        = string
  default     = "snet-container-apps"
}

variable "private_endpoint_subnet_name" {
  description = "The name of the application spoke's private endpoint subnet. Must match a key of the spoke's subnets variable."
  type        = string
  default     = "snet-private-endpoints"
}

variable "hub_subscription_id" {
  description = "The Azure subscription the hub is deployed into, when it differs from this deployment's subscription. Leave null when they share a subscription. This stack's hub lookups run against it, and the deployment identity needs to read the hub's private DNS zones and to write this stack's private endpoint records into them (e.g. Private DNS Zone Contributor)."
  type        = string
  default     = null
}

variable "hub_deployment_name" {
  description = "The workload name of the hub this stack looks up, without the environment (e.g. hub-spoke). Its network and DNS resource groups are looked up as rg-<hub_deployment_name>-<environment>-network and rg-<hub_deployment_name>-<environment>-dns, and its virtual network as vnet-<hub_deployment_name>-<environment>, so it must match the hub stack's deployment_name and the hub must be deployed into the same environment."
  type        = string
  default     = "hub-spoke"
}

variable "monitoring_subscription_id" {
  description = "The Azure subscription the monitoring spoke is deployed into, when it differs from this deployment's subscription. Leave null when they share a subscription. This stack's monitoring lookups run against it; diagnostics and agents reference the workspace by ID, which spans subscriptions."
  type        = string
  default     = null
}

variable "monitoring_deployment_name" {
  description = "The workload name of the monitoring spoke this stack sends diagnostics to, without the environment (e.g. monitoring-spoke). Its resource group and Log Analytics workspace are looked up as rg-<monitoring_deployment_name>-<environment> and log-<monitoring_deployment_name>-<environment>, so it must match the monitoring stack's deployment_name and the monitoring spoke must be deployed into the same environment."
  type        = string
  default     = "monitoring-spoke"
}

variable "zone_redundancy_enabled" {
  description = "Whether the container app environment is spread across availability zones."
  type        = bool
  default     = false
}

variable "container_image" {
  description = "The container image the app runs. The default quickstart image lets the first deployment succeed before any image has been pushed to the registry."
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}

variable "container_target_port" {
  description = "The port the container listens on for ingress traffic."
  type        = number
  default     = 80
}

variable "container_cpu" {
  description = "The CPU cores allocated to the container."
  type        = number
  default     = 0.25
}

variable "container_memory" {
  description = "The memory allocated to the container."
  type        = string
  default     = "0.5Gi"
}

variable "min_replicas" {
  description = "The minimum number of replicas of the container app."
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "The maximum number of replicas of the container app."
  type        = number
  default     = 3
}

variable "container_registry_name" {
  description = "The globally unique name of the container registry. Defaults to cr<deployment_name>-<environment> stripped of hyphens."
  type        = string
  default     = null
}

variable "container_registry_zone_redundancy_enabled" {
  description = "Whether the container registry is spread across availability zones."
  type        = bool
  default     = false
}

variable "container_registry_push_principal_ids" {
  description = "Principal IDs granted the AcrPush role to publish images from inside the network, e.g. a build agents group object ID."
  type        = list(string)
  default     = []
}

variable "key_vault_name" {
  description = "The globally unique name of the key vault. Defaults to kv-<deployment_name>-<environment>, which must stay within the 24 character vault name limit."
  type        = string
  default     = null
}

variable "key_vault_secrets_officer_principal_ids" {
  description = "Principal IDs granted the Key Vault Secrets Officer role to populate secrets from inside the network, e.g. an administrators group object ID."
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
  default     = "CloudEngineering"

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
  default     = "ApplicationPlatform"

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

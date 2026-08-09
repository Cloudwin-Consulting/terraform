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

variable "virtual_machine_subnet_name" {
  description = "The name of the application spoke subnet that hosts Linux virtual machines. Must match a key of the spoke's subnets variable."
  type        = string
  default     = "snet-linux-vm"
}

variable "private_endpoint_subnet_name" {
  description = "The name of the application spoke's private endpoint subnet. Must match a key of the spoke's subnets variable."
  type        = string
  default     = "snet-private-endpoints"
}

variable "application_security_group_role" {
  description = "The role suffix of the application spoke's ASG this workload's machines join: the spoke names its ASGs asg-<app_spoke_deployment_name>-<environment>-<role>, so linux-vm resolves to asg-app-spoke-dev-linux-vm in dev. The spoke's VM subnet NSG allows traffic by ASG membership, so machines should join it. Leave null to skip the association."
  type        = string
  default     = null
}

variable "hub_subscription_id" {
  description = "The Azure subscription the hub is deployed into, when it differs from this deployment's subscription. Leave null when they share a subscription. This stack's hub lookups run against it, and the deployment identity needs to read the hub's private DNS zones and to write this stack's private endpoint records into them (e.g. Private DNS Zone Contributor)."
  type        = string
  default     = null
}

variable "hub_deployment_name" {
  description = "The workload name of the hub this stack looks up, without the environment (e.g. hub-spoke). Its DNS resource group, where the hub keeps its private DNS zones, is looked up as rg-<hub_deployment_name>-<environment>-dns, so it must match the hub stack's deployment_name and the hub must be deployed into the same environment."
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

variable "virtual_machine_count" {
  description = "The number of virtual machines to deploy."
  type        = number
  default     = 1

  validation {
    condition     = var.virtual_machine_count >= 1
    error_message = "virtual_machine_count must be at least 1."
  }
}

variable "virtual_machine_size" {
  description = "The size of the virtual machines."
  type        = string
  default     = "Standard_B2s"
}


variable "availability_zones" {
  description = "Availability zones the virtual machines (and their disks) are distributed across round-robin, e.g. [\"1\", \"2\", \"3\"]. Leave empty for a regional deployment."
  type        = list(string)
  default     = []
}

variable "os_disk" {
  description = "Settings of the operating system disks, including optional customer-managed key encryption through a disk encryption set."
  type = object({
    caching                = optional(string, "ReadWrite")
    storage_account_type   = optional(string, "StandardSSD_LRS")
    disk_size_gb           = optional(number)
    disk_encryption_set_id = optional(string)
  })
  default = {}
}

variable "data_disks" {
  description = "Managed data disks created and attached to each virtual machine, in LUN order. Names are prefixed with the machine name. Disks default to private-only access and support customer-managed key encryption through a disk encryption set."
  type = list(object({
    name                          = string
    disk_size_gb                  = number
    storage_account_type          = optional(string, "StandardSSD_LRS")
    caching                       = optional(string, "ReadWrite")
    tier                          = optional(string)
    disk_encryption_set_id        = optional(string)
    network_access_policy         = optional(string, "DenyAll")
    public_network_access_enabled = optional(bool, false)
    disk_access_id                = optional(string)
  }))
  default = []
}


variable "source_image_id" {
  description = "The ID of a compute gallery image (or image version) the machines are created from. Leave null for the marketplace default."
  type        = string
  default     = null
}

variable "enable_backup" {
  description = "Whether to deploy a Recovery Services vault and protect the virtual machines with its daily backup policy. The vault is only reachable through its private endpoint, so backup_private_endpoint_dns_zone_name is also required."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_backup || var.backup_private_endpoint_dns_zone_name != null
    error_message = "enable_backup requires backup_private_endpoint_dns_zone_name: the vault only accepts traffic through its private endpoint, which needs the geo-specific backup private DNS zone."
  }
}

variable "backup_private_endpoint_dns_zone_name" {
  description = "The name of the hub's geo-specific backup private DNS zone the vault's private endpoint registers into, e.g. privatelink.uks.backup.windowsazure.com for UK South. The hub creates it through additional_private_dns_zone_names."
  type        = string
  default     = null
}

variable "backup_daily_retention_days" {
  description = "Days daily backups are retained."
  type        = number
  default     = 7
}

variable "enable_monitor_agent" {
  description = "Whether to install the Azure Monitor Agent with a default data collection rule sending to the monitoring workspace. Ingestion is private, so the application spoke must be peered with the monitoring spoke."
  type        = bool
  default     = false
}

variable "data_collection_endpoint_name" {
  description = "The name of the data collection endpoint in the monitoring spoke that agents use for private configuration access and ingestion. Defaults to the name the monitoring spoke derives, dce-<monitoring_deployment_name>-<environment>; set it only when that stack's name was overridden."
  type        = string
  default     = null
}

variable "enable_load_balancer" {
  description = "Whether to front the virtual machines with an internal load balancer."
  type        = bool
  default     = false
}

variable "enable_load_balancer_public_ip" {
  description = "Whether the internal load balancer also has an internet-facing frontend IP. Rules only reach it when marked public. The internal frontend is always present."
  type        = bool
  default     = false
}

variable "load_balancer_rules" {
  description = "Load balancing rules for the internal load balancer. Keep the application spoke's virtual_machine_workload_inbound_rules aligned with these ports and protocols, or the subnet NSG blocks the traffic."
  type = list(object({
    name               = string
    protocol           = optional(string, "Tcp")
    frontend_port      = number
    backend_port       = number
    probe_protocol     = optional(string, "Tcp")
    probe_port         = optional(number)
    probe_request_path = optional(string)
  }))
  default = [
    {
      name          = "https"
      frontend_port = 443
      backend_port  = 443
    }
  ]
}

variable "platform_key_vault_subscription_id" {
  description = "The Azure subscription holding the platform key vault this stack reads its secrets from, when it differs from the application spoke's. Leave null to resolve the vault in the application spoke's subscription (app_spoke_subscription_id), which itself defaults to this deployment's. The deployment identity needs read access to the vault there, on top of the data plane access the secrets themselves need."
  type        = string
  default     = null
}

variable "admin_ssh_public_key_key_vault_secret" {
  description = "Reads the admin SSH public key from a secret pre-loaded into the spoke's platform key vault, instead of holding the key in source control. The deployment agent must reach the vault's private data plane, e.g. a self-hosted agent inside the network. Password authentication is disabled. key_vault_name and key_vault_resource_group_name default to the names the spoke derives, kv-<app_spoke_deployment_name>-<environment> and rg-<app_spoke_deployment_name>-<environment>-secrets; set them only when the spoke's platform_key_vault_name was overridden. The vault is resolved in platform_key_vault_subscription_id, defaulting to the application spoke's subscription."
  type = object({
    key_vault_name                = optional(string)
    key_vault_resource_group_name = optional(string)
    secret_name                   = string
  })
}

variable "secure_boot_enabled" {
  description = "Whether trusted launch secure boot is enabled on the virtual machine. The default marketplace image supports trusted launch; set false alongside vtpm_enabled when source_image_id points at a gallery image whose definition is generation 1 or was created with trusted_launch_supported = false, which Azure otherwise refuses to deploy."
  type        = bool
  default     = true
}

variable "vtpm_enabled" {
  description = "Whether the trusted launch virtual TPM is enabled on the virtual machine. Set false alongside secure_boot_enabled for images that do not support trusted launch."
  type        = bool
  default     = true
}

variable "encryption_at_host_enabled" {
  description = "Whether encryption at host is enabled on the virtual machine. Requires the Microsoft.Compute/EncryptionAtHost subscription feature."
  type        = bool
  default     = true
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
  default     = "Compute"

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

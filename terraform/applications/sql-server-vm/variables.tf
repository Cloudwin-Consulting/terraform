variable "deployment_subscription_id" {
  description = "The Azure subscription into which resources will be deployed."
  type        = string
}

variable "deployment_location" {
  description = "The Azure location into which resources will be deployed."
  type        = string
}

variable "deployment_name" {
  description = "The name of the workload being deployed, without the environment (e.g. sql-server-vm). Every resource name is derived from it and environment together - rg-<deployment_name>-<environment> for the resource group, <abbreviation>-<deployment_name>-<environment> for the resources in it - so the pair must be unique across all stacks and environments: a workload name reused in the same environment derives the same resource group name and clashes on globally unique names."
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

variable "database_subnet_name" {
  description = "The name of the application spoke subnet that hosts the database tier. Must match a key of the spoke's subnets variable. Keep the database tier on its own subnet so its NSG can allow SQL traffic from the application tier alone."
  type        = string
  default     = "snet-database"
}

variable "private_endpoint_subnet_name" {
  description = "The name of the application spoke's private endpoint subnet. Must match a key of the spoke's subnets variable."
  type        = string
  default     = "snet-private-endpoints"
}

variable "application_security_group_role" {
  description = "The role suffix of the application spoke's ASG the database machines join: the spoke names its ASGs asg-<app_spoke_deployment_name>-<environment>-<role>, so sql-server resolves to asg-app-spoke-dev-sql-server in dev. The spoke's subnet NSG allows SQL traffic by ASG membership rather than by IP address, so the machines should join it. Leave null to skip the association."
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

# ------------------------------------------------------------
# The database machines
# ------------------------------------------------------------

variable "virtual_machine_count" {
  description = "The number of SQL Server machines to deploy. Each is an independent standalone instance: more than one is useful for sharding or for building an Always On availability group by hand, not for automatic failover, which the shared module supports through its availability group inputs."
  type        = number
  default     = 1

  validation {
    condition     = var.virtual_machine_count >= 1
    error_message = "virtual_machine_count must be at least 1."
  }
}

variable "virtual_machine_size" {
  description = "The size of the database machines. SQL Server wants a memory-optimised size with enough attached-disk throughput to keep the data and log disks fed, e.g. Standard_E4ds_v5."
  type        = string
  default     = "Standard_E4ds_v5"
}

variable "computer_name" {
  description = "The in-guest computer name, at most 15 characters including the index appended when more than one machine is deployed. SQL Server takes its instance name from this."
  type        = string
  default     = "sqlvm"

  validation {
    condition     = length(var.computer_name) + (var.virtual_machine_count > 1 ? length(tostring(var.virtual_machine_count - 1)) : 0) <= 15
    error_message = "computer_name plus the appended machine index must stay within the 15 character Windows computer name limit."
  }
}

variable "availability_zones" {
  description = "Availability zones the machines (and their disks) are distributed across round-robin, e.g. [\"1\", \"2\", \"3\"]. Leave empty for a regional deployment."
  type        = list(string)
  default     = []
}

variable "license_type" {
  description = "The existing Windows Server licence applied through Azure Hybrid Benefit. SQL Server's own licence is set with sql_license_type. Leave null for pay-as-you-go."
  type        = string
  default     = null
}

variable "platform_key_vault_subscription_id" {
  description = "The Azure subscription holding the platform key vault this stack reads its secrets from, when it differs from the application spoke's. Leave null to resolve the vault in the application spoke's subscription (app_spoke_subscription_id), which itself defaults to this deployment's. The deployment identity needs read access to the vault there."
  type        = string
  default     = null
}

variable "admin_password_key_vault_secret" {
  description = "Reads the local administrator password from a secret pre-loaded into the spoke's platform key vault instead of generating one. The deployment agent must reach the vault's private data plane, e.g. a self-hosted agent inside the network. Leave null to generate passwords. key_vault_name and key_vault_resource_group_name default to the names the spoke derives, kv-<app_spoke_deployment_name>-<environment> and rg-<app_spoke_deployment_name>-<environment>-secrets; set them only when the spoke's platform_key_vault_name was overridden."
  type = object({
    key_vault_name                = optional(string)
    key_vault_resource_group_name = optional(string)
    secret_name                   = string
  })
  default = null
}

# ------------------------------------------------------------
# Storage: the data, log and tempdb volumes
# ------------------------------------------------------------

variable "os_disk" {
  description = "Settings of the operating system disks, including optional customer-managed key encryption through a disk encryption set. SQL Server's own files belong on the data disks below, not here."
  type = object({
    caching                = optional(string, "ReadWrite")
    storage_account_type   = optional(string, "StandardSSD_LRS")
    disk_size_gb           = optional(number)
    disk_encryption_set_id = optional(string)
  })
  default = {}
}

variable "data_disks" {
  description = "Managed data disks created for each machine and laid out by the SQL IaaS Agent extension, in LUN order. Names are prefixed with the machine name. Each disk declares the role its volume serves - data, log or temp_db - and disks sharing a role are pooled into one volume, so add disks to a role to scale its throughput past a single disk's limits. Leave caching unset to get the right value for the role: ReadOnly for data and tempdb, None for log."
  type = list(object({
    name                          = string
    disk_size_gb                  = number
    role                          = optional(string, "data")
    storage_account_type          = optional(string, "Premium_LRS")
    caching                       = optional(string)
    tier                          = optional(string)
    disk_encryption_set_id        = optional(string)
    network_access_policy         = optional(string, "DenyAll")
    public_network_access_enabled = optional(bool, false)
    disk_access_id                = optional(string)
  }))

  default = [
    {
      name         = "data"
      disk_size_gb = 256
      role         = "data"
    },
    {
      name         = "log"
      disk_size_gb = 128
      role         = "log"
    },
  ]
}

variable "storage_configuration" {
  description = "How the SQL IaaS Agent extension lays SQL Server's files out over the volumes it builds from the data disks. The default file paths assume the extension's usual drive letters, assigned in role order from F:. Set storage_workload_type to OLTP for transaction processing or DW for data warehousing so the extension tunes the instance for it."
  type = object({
    disk_type                      = optional(string, "NEW")
    storage_workload_type          = optional(string, "GENERAL")
    system_db_on_data_disk_enabled = optional(bool, false)
    data_file_path                 = optional(string, "F:\\data")
    log_file_path                  = optional(string, "G:\\log")
    temp_db_file_path              = optional(string, "H:\\tempDb")
    temp_db = optional(object({
      data_file_count        = optional(number)
      data_file_size_mb      = optional(number)
      data_file_growth_in_mb = optional(number)
      log_file_size_mb       = optional(number)
      log_file_growth_mb     = optional(number)
    }))
  })
  default = {}
}

# ------------------------------------------------------------
# SQL Server
# ------------------------------------------------------------

variable "sql_image_offer" {
  description = "The marketplace offer the machines are built from, pairing a SQL Server release with a Windows Server release, e.g. sql2022-ws2022 or sql2019-ws2022."
  type        = string
  default     = "sql2022-ws2022"
}

variable "sql_image_sku" {
  description = "The SQL Server edition, which must be a generation 2 SKU for trusted launch: standard-gen2, enterprise-gen2, web-gen2, or sqldev-gen2 for the free developer edition (never licensed for production use)."
  type        = string
  default     = "standard-gen2"

  validation {
    condition     = can(regex("-gen2$", var.sql_image_sku))
    error_message = "sql_image_sku must be a generation 2 SKU (ending -gen2): trusted launch, which this stack enables by default, refuses generation 1 images."
  }
}

variable "sql_image_version" {
  description = "The version of the marketplace image. Leave as latest to pick up the newest published build on redeployment."
  type        = string
  default     = "latest"
}

variable "source_image_id" {
  description = "The ID of a compute gallery image (or image version) the machines are created from, e.g. a hardened SQL Server build. Overrides the marketplace image when set."
  type        = string
  default     = null
}

variable "sql_license_type" {
  description = "How the SQL Server licence is paid for: PAYG for pay-as-you-go, AHUB to bring a licence covered by Software Assurance through Azure Hybrid Benefit, or DR for a passive disaster recovery replica. Ignored by the free developer edition."
  type        = string
  default     = "PAYG"
}

variable "sql_connectivity_type" {
  description = "How far SQL Server's TCP listener reaches: LOCAL for the machine itself only, PRIVATE for the virtual network, or PUBLIC for the internet. Keep PRIVATE - PUBLIC exposes the database engine to the internet, which this stack's spoke NSG should be blocking anyway."
  type        = string
  default     = "PRIVATE"

  validation {
    condition     = contains(["LOCAL", "PRIVATE"], var.sql_connectivity_type)
    error_message = "sql_connectivity_type must be LOCAL or PRIVATE in this stack: the database tier is reached over the private network, never from the internet."
  }
}

variable "sql_connectivity_port" {
  description = "The TCP port SQL Server listens on. Keep the spoke's database subnet NSG rules aligned with it."
  type        = number
  default     = 1433
}

variable "enable_sql_authentication" {
  description = "Whether to enable mixed mode authentication and create a SQL login, with a password generated per machine (retrieve with `terraform output -json sql_login_passwords`). Leave false - the secure default - so the instance keeps Windows authentication only, and grant access to domain groups instead. Only enable it for clients that cannot use Windows authentication."
  type        = bool
  default     = false
}

variable "sql_login_username" {
  description = "The username of the SQL login created when enable_sql_authentication is set. Avoid well-known names such as sa, which the shared module rejects."
  type        = string
  default     = "sqlappadmin"
}

variable "r_services_enabled" {
  description = "Whether SQL Server Machine Learning Services (R and Python) is enabled. Keep disabled unless the workload needs it: it runs external scripts on the database host."
  type        = bool
  default     = false
}

variable "sql_instance" {
  description = "Instance-level SQL Server settings applied by the agent, e.g. collation, degree of parallelism and the memory ceiling. Leave null to keep SQL Server's own defaults. Setting max_server_memory_mb is worth doing on a dedicated machine so the engine leaves the operating system room to breathe."
  type = object({
    collation                            = optional(string)
    max_dop                              = optional(number)
    min_server_memory_mb                 = optional(number)
    max_server_memory_mb                 = optional(number)
    instant_file_initialization_enabled  = optional(bool)
    lock_pages_in_memory_enabled         = optional(bool)
    adhoc_workloads_optimization_enabled = optional(bool)
  })
  default = null
}

variable "auto_patching" {
  description = "The weekly maintenance window in which the SQL IaaS agent applies SQL Server and Windows updates. On by default. Set to null to take patching over yourself, e.g. with Azure Update Manager."
  type = object({
    day_of_week                            = optional(string, "Sunday")
    maintenance_window_starting_hour       = optional(number, 2)
    maintenance_window_duration_in_minutes = optional(number, 60)
  })
  default = {}
}

variable "enable_assessment" {
  description = "Whether to run the SQL best practices assessment, which reports configuration and security findings into the monitoring workspace. Requires enable_monitor_agent."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_assessment || var.enable_monitor_agent
    error_message = "enable_assessment requires enable_monitor_agent: the assessment reports its findings through the machine's monitor agent into the monitoring workspace."
  }
}

variable "assessment_schedule" {
  description = "When the best practices assessment runs. Leave null to run it only on demand."
  type = object({
    day_of_week        = string
    start_time         = string
    weekly_interval    = optional(number)
    monthly_occurrence = optional(number)
  })
  default = null
}

# ------------------------------------------------------------
# Backup, monitoring and platform integration
# ------------------------------------------------------------

variable "enable_backup" {
  description = "Whether to deploy a Recovery Services vault and protect the machines with its daily backup policy. The vault is only reachable through its private endpoint, so backup_private_endpoint_dns_zone_name is also required."
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

variable "secure_boot_enabled" {
  description = "Whether trusted launch secure boot is enabled on the machines. The default marketplace image supports trusted launch; set false alongside vtpm_enabled when source_image_id points at a gallery image whose definition is generation 1 or was created with trusted_launch_supported = false, which Azure otherwise refuses to deploy."
  type        = bool
  default     = true
}

variable "vtpm_enabled" {
  description = "Whether the trusted launch virtual TPM is enabled on the machines. Set false alongside secure_boot_enabled for images that do not support trusted launch."
  type        = bool
  default     = true
}

variable "encryption_at_host_enabled" {
  description = "Whether encryption at host is enabled on the machines. Requires the Microsoft.Compute/EncryptionAtHost subscription feature."
  type        = bool
  default     = true
}

variable "key_vault_name" {
  description = "The globally unique name of the application key vault. Defaults to kv-<deployment_name>-<environment>, which must stay within the 24 character vault name limit."
  type        = string
  default     = null
}

variable "key_vault_secrets_officer_principal_ids" {
  description = "Principal IDs granted the Key Vault Secrets Officer role to populate secrets from inside the network, e.g. a database administrators group object ID."
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
  default     = "Data"

  validation {
    condition     = contains(["Networking", "Monitoring", "ApplicationPlatform", "Integration", "Data", "Compute", "Management", "EndUserComputing", "EntryPoint"], var.service)
    error_message = "service must be one of: Networking, Monitoring, ApplicationPlatform, Integration, Data, Compute, Management, EndUserComputing, EntryPoint."
  }
}

variable "data_classification" {
  description = "The value of the DataClassification tag: the most sensitive data this deployment holds."
  type        = string
  default     = "Confidential"

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

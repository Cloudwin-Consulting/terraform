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
  description = "The name of the application spoke subnet that hosts Windows virtual machines. Must match a key of the spoke's subnets variable."
  type        = string
  default     = "snet-windows-vm"
}

variable "private_endpoint_subnet_name" {
  description = "The name of the application spoke's private endpoint subnet. Must match a key of the spoke's subnets variable."
  type        = string
  default     = "snet-private-endpoints"
}

variable "application_security_group_role" {
  description = "The role suffix of the application spoke's ASG this workload's machines join: the spoke names its ASGs asg-<app_spoke_deployment_name>-<environment>-<role>, so windows-vm resolves to asg-app-spoke-dev-windows-vm in dev. The spoke's VM subnet NSG allows the machines' SMB traffic to the private endpoint subnet by ASG membership, so machines that skip the association cannot reach the share. Leave null to skip the association."
  type        = string
  default     = null
}

variable "hub_subscription_id" {
  description = "The Azure subscription the hub is deployed into, when it differs from this deployment's subscription. Leave null when they share a subscription. This stack's hub lookups run against it, and the deployment identity needs to read the hub's private DNS zones and to write this stack's private endpoint records into them (e.g. Private DNS Zone Contributor)."
  type        = string
  default     = null
}

variable "hub_deployment_name" {
  description = "The workload name of the hub this stack looks up, without the environment (e.g. hub-spoke). Its DNS resource group, where the hub keeps the privatelink.file.core.windows.net zone this stack's private endpoint registers in, is looked up as rg-<hub_deployment_name>-<environment>-dns, so it must match the hub stack's deployment_name and the hub must be deployed into the same environment."
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
# The storage account and its SMB file share
# ------------------------------------------------------------

variable "storage_account_name" {
  description = "The globally unique name of the storage account. Defaults to st<deployment_name><environment> with the hyphens removed, which must stay within the 24 character storage account name limit."
  type        = string
  default     = null
}

variable "storage_account_replication_type" {
  description = "The replication type of the storage account. Zone-redundant storage (ZRS) keeps the share available through the loss of a datacentre in the region; LRS is cheaper and enough for files that can be rebuilt."
  type        = string
  default     = "ZRS"
}

variable "file_share_name" {
  description = "The name of the SMB file share the application's files are saved on. It is part of the UNC path the machines mount (\\\\<storage account>.file.core.windows.net\\<file_share_name>), so renaming it moves every machine to a new, empty share."
  type        = string
  default     = "appdata"

  validation {
    condition     = length(var.file_share_name) >= 3 && length(var.file_share_name) <= 63 && can(regex("^[a-z0-9](-?[a-z0-9])*$", var.file_share_name))
    error_message = "file_share_name must be 3-63 characters of lowercase letters, numbers and single hyphens, starting and ending alphanumeric."
  }
}

variable "file_share_quota_gb" {
  description = "The maximum size of the file share in GB. On a standard account this is a billed ceiling rather than a reservation: the share is charged for the data actually stored, and writes past the quota fail, so size it above the application's expected growth."
  type        = number
  default     = 100
}

variable "file_share_access_tier" {
  description = "The access tier of the file share. TransactionOptimized suits write-heavy application data, Hot general purpose file shares and Cool infrequently read archives; the tiers trade storage cost against transaction cost."
  type        = string
  default     = "TransactionOptimized"

  validation {
    condition     = contains(["TransactionOptimized", "Hot", "Cool"], var.file_share_access_tier)
    error_message = "file_share_access_tier must be TransactionOptimized, Hot or Cool (Premium needs a FileStorage account, which the storage-account module does not create)."
  }
}

variable "file_share_drive_letter" {
  description = "The drive letter the share is mapped to on each machine, e.g. F. The mapping is machine-wide and persistent, so applications and services address the share as <letter>:\\ regardless of which user they run as. E to Z only: A and B are the machine's floppy letters, C its operating system disk and D the Azure temporary disk, which is present on most VM sizes."
  type        = string
  default     = "F"

  validation {
    condition     = can(regex("^[E-Z]$", var.file_share_drive_letter))
    error_message = "file_share_drive_letter must be a single letter between E and Z: A to C are the machine's own drives and D is the Azure temporary disk."
  }
}

variable "azure_files_authentication" {
  description = "Identity-based authentication for the share, so the machines mount it as their own directory identities and no account key exists anywhere. Leave null - the default - to mount with the account key instead, which is what a workgroup machine has to use; the key is then generated by Azure, kept in the Terraform state and delivered to each machine as an encrypted protected parameter. directory_type AD serves domain-joined machines (set domain_join too, and pre-create the storage account's AD account with the AzFilesHybrid PowerShell module, which is where domain_guid and the SIDs come from), and AADDS the same for a Microsoft Entra Domain Services domain. AADKERB serves Microsoft Entra joined machines and needs an administrator to grant admin consent to the account's auto-created Entra application after the first deployment; the machines this stack deploys are never Entra joined, so it is only accepted alongside virtual_machine_count = 0, for a share mounted by Entra joined machines elsewhere (the avd stack's session hosts, for instance). Set default_share_level_permission (e.g. StorageFileDataSmbShareContributor) to authorise every authenticated identity, including the machine accounts doing the mounting, instead of naming them in share_contributor_principals."
  type = object({
    directory_type                 = string
    default_share_level_permission = optional(string)
    active_directory = optional(object({
      domain_name         = string
      domain_guid         = string
      domain_sid          = optional(string)
      storage_sid         = optional(string)
      forest_name         = optional(string)
      netbios_domain_name = optional(string)
    }))
  })
  default = null

  # The machines this stack deploys are workgroup-joined, or joined to
  # Active Directory through domain_join - it has no Entra join of its
  # own, and Entra Kerberos tickets need one. AADKERB is therefore only
  # accepted for a share this stack does not mount itself, e.g. one
  # mounted by the Entra joined session hosts of the avd stack.
  validation {
    condition     = try(var.azure_files_authentication.directory_type, null) != "AADKERB" || var.virtual_machine_count == 0
    error_message = "azure_files_authentication with directory_type AADKERB requires Microsoft Entra joined machines, which this stack does not deploy: set virtual_machine_count = 0 and mount the share from Entra joined machines elsewhere, or use directory_type AD with domain_join for the machines this stack owns."
  }

  # Identity-based authentication leaves the account with no usable
  # key, so a machine this stack deploys can only mount the share once
  # it holds a directory identity of its own. Without domain_join it
  # stays in a workgroup, has no way to obtain a Kerberos ticket, and
  # its mount would fail after exhausting the script's retries - so
  # the mismatch is caught here instead, at plan time. AADDS is a
  # domain like any other as far as the machines are concerned: they
  # join a Microsoft Entra Domain Services domain with the same run
  # command, given a join account in that domain.
  validation {
    condition     = !contains(["AD", "AADDS"], try(var.azure_files_authentication.directory_type, "")) || var.virtual_machine_count == 0 || var.domain_join != null
    error_message = "azure_files_authentication with directory_type AD or AADDS requires domain_join while this stack deploys machines: they mount the share as their own domain identities, which a workgroup machine has none of. Set domain_join, or set virtual_machine_count = 0 to deploy the share for machines joined elsewhere."
  }

  # A domain identity is only half of it: the identity also has to be
  # authorised on the share, and with no key to fall back on an
  # unauthorised mount is refused every time. The machines mount as
  # their computer accounts, whose object IDs this deployment cannot
  # know at plan time, so they are authorised either by the account's
  # default share-level permission or through a group they belong to.
  validation {
    condition = (
      !contains(["AD", "AADDS"], try(var.azure_files_authentication.directory_type, "")) ||
      var.virtual_machine_count == 0 ||
      try(var.azure_files_authentication.default_share_level_permission, null) != null ||
      length(var.share_contributor_principals) > 0 ||
      length(var.share_admin_principals) > 0
    )
    error_message = "Identity-based authentication grants the machines nothing on its own, and there is no account key to fall back on: set azure_files_authentication.default_share_level_permission (StorageFileDataSmbShareContributor authorises every authenticated identity, the machine accounts among them), or name a group holding the machines in share_contributor_principals or share_admin_principals."
  }
}

variable "share_contributor_principals" {
  description = "Principals granted Storage File Data SMB Share Contributor on the account - read and write access to the files on the share - keyed by a static label naming each assignment, e.g. { app-operators = \"<object id>\" }. Only meaningful with azure_files_authentication set: a machine mounting with the account key is authorised by the key alone."
  type        = map(string)
  default     = {}
}

variable "share_admin_principals" {
  description = "Principals granted Storage File Data SMB Share Elevated Contributor on the account, keyed by a static label. The elevated role adds control of the share's NTFS ACLs, which is how an application's directory layout and permissions are set up over SMB while shared key access is disabled."
  type        = map(string)
  default     = {}
}

variable "share_principal_type" {
  description = "The type of every principal in share_contributor_principals and share_admin_principals: User, Group or ServicePrincipal. Group suits the administrators and application identities these roles are normally granted to."
  type        = string
  default     = "Group"

  validation {
    condition     = contains(["User", "Group", "ServicePrincipal"], var.share_principal_type)
    error_message = "share_principal_type must be one of: User, Group, ServicePrincipal."
  }
}

# ------------------------------------------------------------
# The Windows machines the share is mounted on
# ------------------------------------------------------------

variable "virtual_machine_count" {
  description = "The number of Windows virtual machines to deploy and mount the share on. Set 0 to deploy the share on its own, for machines another stack owns."
  type        = number
  default     = 1

  validation {
    condition     = var.virtual_machine_count >= 0
    error_message = "virtual_machine_count must be zero or more."
  }
}

variable "virtual_machine_size" {
  description = "The size of the virtual machines."
  type        = string
  default     = "Standard_B2s"
}

variable "computer_name" {
  description = "The in-guest computer name, at most 15 characters including the index appended when more than one machine is deployed."
  type        = string
  default     = "vmappfiles"

  validation {
    condition     = length(var.computer_name) + (var.virtual_machine_count > 1 ? length(tostring(var.virtual_machine_count - 1)) : 0) <= 15
    error_message = "computer_name plus the appended machine index must stay within the 15 character Windows computer name limit."
  }
}

variable "platform_key_vault_subscription_id" {
  description = "The Azure subscription holding the platform key vault this stack reads its secrets from, when it differs from the application spoke's. Leave null to resolve the vault in the application spoke's subscription (app_spoke_subscription_id), which itself defaults to this deployment's. The deployment identity needs read access to the vault there and, when domain_join is used, role assignment write at its scope (e.g. Role Based Access Control Administrator), because the stack grants each machine Key Vault Secrets User on the vault."
  type        = string
  default     = null
}

variable "admin_password_key_vault_secret" {
  description = "Reads the admin password from a secret pre-loaded into the spoke's platform key vault instead of generating one. The deployment agent must reach the vault's private data plane, e.g. a self-hosted agent inside the network. Leave null to generate passwords. key_vault_name and key_vault_resource_group_name default to the names the spoke derives, kv-<app_spoke_deployment_name>-<environment> and rg-<app_spoke_deployment_name>-<environment>-secrets; set them only when the spoke's platform_key_vault_name was overridden. The vault is resolved in platform_key_vault_subscription_id, defaulting to the application spoke's subscription."
  type = object({
    key_vault_name                = optional(string)
    key_vault_resource_group_name = optional(string)
    secret_name                   = string
  })
  default = null
}

variable "domain_join" {
  description = "Joins the machines to an Active Directory domain with the repository's join-domain.ps1 run command, which is what lets them mount the share as their own directory identities when azure_files_authentication uses directory_type AD. Each machine fetches the join account's username and password itself at runtime, from secrets pre-loaded into the spoke's platform key vault, using its managed identity - the secret values never pass through Terraform or its state. The machines must be able to resolve and reach the domain: point the application spoke's dns_servers at the domain controllers (or a resolver that forwards to them) and set its active_directory_outbound_address_prefixes so the NSG allows the AD traffic. Leave null to keep the machines workgroup-joined. key_vault_name and key_vault_resource_group_name default to the names the spoke derives, kv-<app_spoke_deployment_name>-<environment> and rg-<app_spoke_deployment_name>-<environment>-secrets; set them only when the spoke's platform_key_vault_name was overridden. The vault is resolved in platform_key_vault_subscription_id, defaulting to the application spoke's subscription."
  type = object({
    domain_name                   = string
    ou_path                       = optional(string)
    key_vault_name                = optional(string)
    key_vault_resource_group_name = optional(string)
    username_secret_name          = string
    password_secret_name          = string
  })
  default = null
}

variable "availability_zones" {
  description = "Availability zones the virtual machines (and their disks) are distributed across round-robin, e.g. [\"1\", \"2\", \"3\"]. Leave empty for a regional deployment. The share itself is made zone redundant through storage_account_replication_type, not this."
  type        = list(string)
  default     = []
}

variable "os_disk" {
  description = "Settings of the operating system disks, including optional customer-managed key encryption through a disk encryption set. The machines need no data disks: the application's files are saved on the share."
  type = object({
    caching                = optional(string, "ReadWrite")
    storage_account_type   = optional(string, "StandardSSD_LRS")
    disk_size_gb           = optional(number)
    disk_encryption_set_id = optional(string)
  })
  default = {}
}

variable "source_image_id" {
  description = "The ID of a compute gallery image (or image version) the machines are created from, e.g. a version published by the golden-image stack. Leave null for the marketplace default."
  type        = string
  default     = null
}

variable "secure_boot_enabled" {
  description = "Whether trusted launch secure boot is enabled on the virtual machines. The default marketplace image supports trusted launch; set false alongside vtpm_enabled when source_image_id points at a gallery image whose definition is generation 1 or was created with trusted_launch_supported = false, which Azure otherwise refuses to deploy."
  type        = bool
  default     = true
}

variable "vtpm_enabled" {
  description = "Whether the trusted launch virtual TPM is enabled on the virtual machines. Set false alongside secure_boot_enabled for images that do not support trusted launch."
  type        = bool
  default     = true
}

variable "encryption_at_host_enabled" {
  description = "Whether encryption at host is enabled on the virtual machines. Requires the Microsoft.Compute/EncryptionAtHost subscription feature."
  type        = bool
  default     = true
}

variable "enable_monitor_agent" {
  description = "Whether to install the Azure Monitor Agent on the machines with a default data collection rule sending to the monitoring workspace. Ingestion is private, so the application spoke must be peered with the monitoring spoke. The share's own file service request logs reach the workspace whatever this is set to, through the storage account's diagnostic settings."
  type        = bool
  default     = false
}

variable "data_collection_endpoint_name" {
  description = "The name of the data collection endpoint in the monitoring spoke that agents use for private configuration access and ingestion. Defaults to the name the monitoring spoke derives, dce-<monitoring_deployment_name>-<environment>; set it only when that stack's name was overridden."
  type        = string
  default     = null
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

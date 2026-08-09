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
  description = "The Azure subscription the application spoke is deployed into, when it differs from this deployment's subscription. Leave null when they share a subscription. This stack's spoke lookups run against it, and the deployment identity needs read access to the referenced spoke resources there, plus join permission on the session host subnet."
  type        = string
  default     = null
}

variable "app_spoke_deployment_name" {
  description = "The workload name of the application spoke this stack deploys into, without the environment (e.g. app-spoke). Its network resource group and virtual network are looked up as rg-<app_spoke_deployment_name>-<environment>-network and vnet-<app_spoke_deployment_name>-<environment>, so it must match the spoke stack's deployment_name and the spoke must be deployed into the same environment. A name that does not match fails this stack's lookups at plan time."
  type        = string
  default     = "app-spoke"
}

variable "session_host_subnet_name" {
  description = "The name of the application spoke subnet that hosts the session hosts. The spoke's Windows VM subnet already carries the rules session hosts need - outbound HTTPS for the AVD control plane, SMB to the private endpoints for the profile share, KMS, NTP and DNS - so it is the default. Must match a key of the spoke's subnets variable."
  type        = string
  default     = "snet-windows-vm"
}

variable "private_endpoint_subnet_name" {
  description = "The name of the application spoke's private endpoint subnet, hosting the FSLogix storage private endpoint. Must match a key of the spoke's subnets variable."
  type        = string
  default     = "snet-private-endpoints"
}

variable "application_security_group_role" {
  description = "The role suffix of the application spoke's ASG the session hosts join: the spoke names its ASGs asg-<app_spoke_deployment_name>-<environment>-<role>, so windows-vm resolves to asg-app-spoke-dev-windows-vm in dev. The spoke's VM subnet NSG allows traffic by ASG membership, so session hosts should join it. Leave null to skip the association."
  type        = string
  default     = null
}

variable "hub_subscription_id" {
  description = "The Azure subscription the hub is deployed into, when it differs from this deployment's subscription. Leave null when they share a subscription. This stack's hub lookups run against it, and the deployment identity needs to read the hub's private DNS zones and to write the FSLogix private endpoint's records into them (e.g. Private DNS Zone Contributor)."
  type        = string
  default     = null
}

variable "hub_deployment_name" {
  description = "The workload name of the hub this stack looks up, without the environment (e.g. hub-spoke). Its DNS resource group, where the hub keeps its private DNS zones, is looked up as rg-<hub_deployment_name>-<environment>-dns, so it must match the hub stack's deployment_name and the hub must be deployed into the same environment."
  type        = string
  default     = "hub-spoke"
}

variable "monitoring_subscription_id" {
  description = "The Azure subscription the monitoring spoke is deployed into, when it differs from this deployment's subscription. Leave null when they share a subscription. This stack's monitoring lookups run against it; the AVD control plane diagnostics and the session hosts' data collection rule reference the workspace and endpoint by ID, which span subscriptions."
  type        = string
  default     = null
}

variable "monitoring_deployment_name" {
  description = "The workload name of the monitoring spoke this stack sends diagnostics to, without the environment (e.g. monitoring-spoke). Its resource group and Log Analytics workspace are looked up as rg-<monitoring_deployment_name>-<environment> and log-<monitoring_deployment_name>-<environment>, so it must match the monitoring stack's deployment_name and the monitoring spoke must be deployed into the same environment. The AVD host pool, application group and workspace logs land there, where AVD Insights reads them."
  type        = string
  default     = "monitoring-spoke"
}

variable "host_pool_type" {
  description = "The type of the host pool: Pooled shares each session host between users, Personal dedicates a session host to each user."
  type        = string
  default     = "Pooled"
}

variable "host_pool_load_balancer_type" {
  description = "How new sessions are distributed across the session hosts: BreadthFirst spreads them across all hosts, DepthFirst fills one host to maximum_sessions_allowed before the next. A Personal host pool must use Persistent."
  type        = string
  default     = "BreadthFirst"
}

variable "maximum_sessions_allowed" {
  description = "The maximum number of user sessions per session host in a pooled host pool."
  type        = number
  default     = 8
}

variable "host_pool_friendly_name" {
  description = "The friendly name of the host pool, shown in the AVD clients."
  type        = string
  default     = null
}

variable "workspace_friendly_name" {
  description = "The friendly name of the workspace, shown in the AVD clients."
  type        = string
  default     = null
}

variable "desktop_friendly_name" {
  description = "The display name of the published desktop, shown in the AVD clients."
  type        = string
  default     = "Desktop"
}

variable "start_vm_on_connect" {
  description = "Whether a user connecting to the pool starts a stopped or deallocated session host. Requires avd_service_principal_object_id, so the service holds the power management role."
  type        = bool
  default     = false

  validation {
    condition     = !var.start_vm_on_connect || var.avd_service_principal_object_id != null
    error_message = "start_vm_on_connect requires avd_service_principal_object_id: the Azure Virtual Desktop service principal powers the hosts on and needs the Desktop Virtualization Power On Off Contributor role."
  }
}

variable "validate_environment" {
  description = "Whether the host pool is a validation environment, receiving AVD service updates before production host pools."
  type        = bool
  default     = false
}

variable "custom_rdp_properties" {
  description = "The RDP properties applied to connections, as a semicolon-separated string. The default marks the hosts as Microsoft Entra joined (so clients on non-Entra devices can connect) and disables drive, clipboard and printer redirection out of the session."
  type        = string
  default     = "targetisaadjoined:i:1;drivestoredirect:s:;redirectclipboard:i:0;redirectprinters:i:0"
}

variable "session_host_count" {
  description = "The number of session hosts to deploy."
  type        = number
  default     = 1

  validation {
    condition     = var.session_host_count >= 1
    error_message = "session_host_count must be at least 1."
  }
}

variable "session_host_size" {
  description = "The size of the session hosts. Size for the expected concurrent sessions per host (maximum_sessions_allowed) rather than for a single user."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "computer_name_prefix" {
  description = "The in-guest computer name prefix; each session host appends its index. Must stay within the 15 character Windows computer name limit including the index."
  type        = string
  default     = "vmavd"

  validation {
    condition     = length(var.computer_name_prefix) + length(tostring(var.session_host_count - 1)) <= 15
    error_message = "computer_name_prefix plus the appended host index must stay within the 15 character Windows computer name limit."
  }
}

variable "availability_zones" {
  description = "Availability zones the session hosts (and their disks) are distributed across round-robin, e.g. [\"1\", \"2\", \"3\"]. Leave empty for a regional deployment."
  type        = list(string)
  default     = []
}

variable "os_disk" {
  description = "Settings of the session hosts' operating system disks, including optional customer-managed key encryption through a disk encryption set. Session hosts are stateless - profiles live on the FSLogix share - so there are no data disks."
  type = object({
    caching                = optional(string, "ReadWrite")
    storage_account_type   = optional(string, "StandardSSD_LRS")
    disk_size_gb           = optional(number)
    disk_encryption_set_id = optional(string)
  })
  default = {}
}

variable "source_image_id" {
  description = "The ID of a compute gallery image (or image version) the session hosts are created from, e.g. a golden image with applications baked in. Leave null for the marketplace default."
  type        = string
  default     = null
}

variable "source_image_reference" {
  description = "The marketplace image the session hosts are created from. The default is Windows 11 multi-session with Microsoft 365 Apps, which ships with the FSLogix agent installed."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "office-365"
    sku       = "win11-24h2-avd-m365"
    version   = "latest"
  }
}

variable "license_type" {
  description = "The licence applied to the session hosts through Azure Hybrid Benefit. Windows_Client covers hosts whose users hold eligible Microsoft 365 or Windows per-user licences - the usual AVD licensing - so it is the default. Set Windows_Server when source_image_id points at a Windows Server image covered by Software Assurance, or null for pay-as-you-go."
  type        = string
  default     = "Windows_Client"
}

variable "encryption_at_host_enabled" {
  description = "Whether encryption at host is enabled on the session hosts. Requires the Microsoft.Compute/EncryptionAtHost subscription feature."
  type        = bool
  default     = true
}

variable "avd_users_group_object_id" {
  description = "The object ID of a Microsoft Entra ID group holding the desktop's users. The group is granted Desktop Virtualization User on the application group, Virtual Machine User Login on the resource group and - with FSLogix enabled - Storage File Data SMB Share Contributor on the profile storage. Leave null to grant access later by hand. Deploying the grants needs role assignment write access (e.g. Owner or User Access Administrator) beyond Contributor."
  type        = string
  default     = null
}

variable "avd_service_principal_object_id" {
  description = "The object ID of the Azure Virtual Desktop first-party service principal in this tenant (application ID 9cdead84-a844-4324-93f2-b2e6bb768d07; look it up with `az ad sp show --id 9cdead84-a844-4324-93f2-b2e6bb768d07 --query id`). Granted the Desktop Virtualization Power On Off Contributor role on the resource group, which the scaling plan and start VM on connect require. Leave null when neither is used."
  type        = string
  default     = null
}

variable "enable_scaling_plan" {
  description = "Whether to deploy a scaling plan that starts and deallocates the session hosts on a working-week schedule. Requires avd_service_principal_object_id, so the service holds the power management role."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_scaling_plan || var.avd_service_principal_object_id != null
    error_message = "enable_scaling_plan requires avd_service_principal_object_id: the Azure Virtual Desktop service principal manages host power and needs the Desktop Virtualization Power On Off Contributor role."
  }

  validation {
    condition     = !var.enable_scaling_plan || var.host_pool_type == "Pooled"
    error_message = "enable_scaling_plan requires a Pooled host pool: scaling plans with pooled schedules cannot manage a Personal host pool."
  }
}

variable "scaling_plan_time_zone" {
  description = "The Windows time zone the scaling plan's schedules run in, e.g. GMT Standard Time."
  type        = string
  default     = "GMT Standard Time"
}

variable "scaling_plan_schedules" {
  description = "The scaling plan's schedules. Leave null for the avd-scaling-plan module's worked full-week default: weekdays ramp up from 07:00, peak from 09:00 and drain from 18:00, signing remaining users out after a 30 minute warning so disconnected sessions cannot hold a host up overnight; weekends keep no host warm and drain on-demand starts (e.g. start VM on connect) the same way. FSLogix keeps a signed-out user's profile safe on the share."
  type = list(object({
    name         = string
    days_of_week = list(string)

    ramp_up_start_time                 = string
    ramp_up_load_balancing_algorithm   = string
    ramp_up_minimum_hosts_percent      = number
    ramp_up_capacity_threshold_percent = number

    peak_start_time               = string
    peak_load_balancing_algorithm = string

    ramp_down_start_time                 = string
    ramp_down_load_balancing_algorithm   = string
    ramp_down_minimum_hosts_percent      = number
    ramp_down_capacity_threshold_percent = number
    ramp_down_force_logoff_users         = bool
    ramp_down_wait_time_minutes          = number
    ramp_down_notification_message       = string
    ramp_down_stop_hosts_when            = string

    off_peak_start_time               = string
    off_peak_load_balancing_algorithm = string
  }))
  default = null
}

variable "enable_fslogix" {
  description = "Whether to deploy the FSLogix profile storage - an Azure file share behind a private endpoint, authenticated with Microsoft Entra Kerberos - and point the session hosts at it. Pooled desktops without it give every user a throwaway local profile. The configuration script runs on every session host either way and reconciles the guest with this setting, so turning it off on an existing deployment disables profiles on the retained hosts instead of leaving them pointed at the share being destroyed. The script only configures the FSLogix agent, never installs it: the marketplace multi-session images ship with it, and custom source_image_id images must have it baked in or the script fails the deployment."
  type        = bool
  default     = true
}

variable "fslogix_storage_account_name" {
  description = "The globally unique name of the FSLogix storage account. Defaults to st<deployment_name>-<environment> without hyphens, suffixed fsl, which must stay within the 24 character storage account name limit."
  type        = string
  default     = null
}

variable "fslogix_storage_replication_type" {
  description = "The replication type of the FSLogix storage account."
  type        = string
  default     = "ZRS"
}

variable "fslogix_profiles_share_quota_gb" {
  description = "The quota of the FSLogix profile share in GB. Size for around 5-10 GB per expected concurrent user."
  type        = number
  default     = 100
}

variable "fslogix_admins_group_object_id" {
  description = "The object ID of a Microsoft Entra ID group of profile share administrators, granted Storage File Data SMB Share Elevated Contributor on the FSLogix storage account. Members can mount the share with full control and manage its NTFS ACLs - e.g. applying the recommended FSLogix hardening that stops users browsing each other's containers. The account disables shared key access, so this role is the only elevated path to the ACLs. Leave null to keep the share's default ACLs, which already let users create their own profile containers."
  type        = string
  default     = null
}

variable "enable_monitor_agent" {
  description = "Whether to install the Azure Monitor Agent on the session hosts with a shared AVD Insights data collection rule - the session host event channels plus session, input delay, network and machine counters - sending to the monitoring workspace. Ingestion is private, so the application spoke must be peered with the monitoring spoke."
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
  default     = "EndUserComputing"

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

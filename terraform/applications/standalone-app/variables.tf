variable "deployment_subscription_id" {
  description = "The Azure subscription into which resources will be deployed."
  type        = string
}

variable "deployment_location" {
  description = "The Azure location into which resources will be deployed."
  type        = string
}

variable "deployment_name" {
  description = "The name of the workload being deployed, without the environment (e.g. standalone-app). Every resource name is derived from it and environment together - rg-<deployment_name>-<environment> for the resource group, <abbreviation>-<deployment_name>-<environment> for the resources in it - so the pair must be unique across all stacks and environments: a workload name reused in the same environment derives the same resource group name and clashes on globally unique names. Keep <deployment_name>-<environment> to 21 characters or fewer, so the derived key vault and storage account names stay inside those services' 24 character limits."
  type        = string
}

variable "environment" {
  description = "The environment this deployment targets (e.g. rd, dev, qa, prod). It is appended to deployment_name to derive every resource name, so a single configuration targets any environment by changing this value alone. This stack looks nothing up in other stacks, so there are no upstream deployments that have to be in the same environment."
  type        = string
}

# ------------------------------------------------------------
# Network
# ------------------------------------------------------------

variable "address_space" {
  description = "The address space of the application's virtual network. Take the range from whoever runs the platform network: this stack creates no peering, so the hub peers to this network from its own side and the range has to be free across everything that hub routes."
  type        = list(string)
  default     = ["10.241.0.0/22"]
}

variable "dns_servers" {
  description = "Custom DNS servers for the virtual network, e.g. the platform's DNS Private Resolver inbound endpoint or domain controllers. Leave empty to use Azure-provided DNS, which resolves the private DNS zones linked to this network. Setting custom servers means those servers must be able to resolve every privatelink zone this application uses, or its private endpoints stop resolving privately."
  type        = list(string)
  default     = []
}

variable "subnets" {
  description = "The subnets of the application's virtual network, keyed by subnet name. The three roles the stack expects are named by private_endpoint_subnet_name, virtual_machine_subnet_name and app_service_subnet_name; the App Service subnet must be delegated to Microsoft.Web/serverFarms. Add further subnets here and they are created, but nothing associates a network security group with them."
  type = map(object({
    address_prefixes                              = list(string)
    service_endpoints                             = optional(list(string), [])
    private_endpoint_network_policies             = optional(string, "Enabled")
    private_link_service_network_policies_enabled = optional(bool, true)
    delegation = optional(object({
      name         = string
      service_name = string
      actions      = optional(list(string), ["Microsoft.Network/virtualNetworks/subnets/action"])
    }), null)
  }))
  default = {
    "snet-private-endpoints" = {
      address_prefixes = ["10.241.0.0/24"]
    }
    "snet-virtual-machines" = {
      address_prefixes = ["10.241.1.0/24"]
    }
    "snet-app-service" = {
      address_prefixes = ["10.241.2.0/26"]
      delegation = {
        name         = "appservice"
        service_name = "Microsoft.Web/serverFarms"
      }
    }
  }

  validation {
    condition     = alltrue([for name, subnet in var.subnets : length(subnet.address_prefixes) > 0 && alltrue([for prefix in subnet.address_prefixes : can(cidrhost(prefix, 0))])])
    error_message = "Every subnet needs at least one valid CIDR prefix."
  }
}

variable "private_endpoint_subnet_name" {
  description = "The name of the subnet every private endpoint in this application lands in. Must match a key of the subnets variable."
  type        = string
  default     = "snet-private-endpoints"

  validation {
    condition     = contains(keys(var.subnets), var.private_endpoint_subnet_name)
    error_message = "private_endpoint_subnet_name must name one of the subnets in the subnets variable."
  }
}

variable "virtual_machine_subnet_name" {
  description = "The name of the subnet both virtual machine tiers deploy into. The tiers are separated by application security group membership rather than by subnet, so one subnet - and one network security group - covers both. Must match a key of the subnets variable."
  type        = string
  default     = "snet-virtual-machines"

  validation {
    condition     = contains(keys(var.subnets), var.virtual_machine_subnet_name)
    error_message = "virtual_machine_subnet_name must name one of the subnets in the subnets variable."
  }
}

variable "app_service_subnet_name" {
  description = "The name of the delegated subnet the web app uses for regional virtual network integration. Must match a key of the subnets variable and be delegated to Microsoft.Web/serverFarms."
  type        = string
  default     = "snet-app-service"

  validation {
    condition     = contains(keys(var.subnets), var.app_service_subnet_name)
    error_message = "app_service_subnet_name must name one of the subnets in the subnets variable."
  }

  validation {
    condition = (
      !contains(keys(var.subnets), var.app_service_subnet_name) ||
      try(var.subnets[var.app_service_subnet_name].delegation.service_name, null) == "Microsoft.Web/serverFarms"
    )
    error_message = "The App Service subnet must be delegated to Microsoft.Web/serverFarms: regional virtual network integration only accepts a delegated subnet."
  }

  # The three roles must land in three different subnets. Azure allows
  # one network security group per subnet, so two roles sharing one
  # would leave this stack's network security groups fighting over the
  # same association; and a subnet delegated to App Service can host
  # neither virtual machine interfaces nor private endpoints. Caught
  # here rather than at apply time, where it surfaces as an association
  # conflict or a delegation error against a half-built network.
  validation {
    condition = length(distinct([
      var.private_endpoint_subnet_name,
      var.virtual_machine_subnet_name,
      var.app_service_subnet_name,
    ])) == 3
    error_message = "private_endpoint_subnet_name, virtual_machine_subnet_name and app_service_subnet_name must each name a different subnet: a subnet takes only one network security group, and the delegated App Service subnet can host neither virtual machine interfaces nor private endpoints."
  }
}

variable "management_source_address_prefixes" {
  description = "The addresses management traffic to the virtual machines arrives from, e.g. the platform hub's Azure Bastion subnet or a management network. SSH is allowed to the Linux tier and RDP to the Windows tier from these prefixes and nowhere else. Leave empty to create neither rule, which leaves the machines reachable over the network by nothing but the workload rules."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for prefix in var.management_source_address_prefixes : can(cidrhost(prefix, 0))])
    error_message = "management_source_address_prefixes must contain valid CIDR prefixes."
  }
}

variable "application_tier_port_ranges" {
  description = "The ports the Windows application tier accepts connections from the Linux web tier on."
  type        = list(string)
  default     = ["8080"]

  validation {
    condition     = length(var.application_tier_port_ranges) > 0
    error_message = "application_tier_port_ranges must name at least one port: an empty list would make the rule match nothing."
  }
}

# ------------------------------------------------------------
# Private DNS
# ------------------------------------------------------------

variable "create_private_dns_zones" {
  description = "Whether this stack creates the private DNS zones its private endpoints need and links them to its own virtual network. Turn it off where the platform registers private endpoints centrally - for instance with an Azure Policy deployIfNotExists assignment - so the endpoints are created without a DNS zone group and the policy owns the records. Zones named in existing_private_dns_zone_ids are never created here, whatever this is set to."
  type        = bool
  default     = true
}

variable "existing_private_dns_zone_ids" {
  description = "Resource IDs of private DNS zones that already exist, keyed by zone name (e.g. { \"privatelink.database.windows.net\" = \"/subscriptions/.../privateDnsZones/privatelink.database.windows.net\" }). Use it where the platform owns a zone: this stack writes its endpoints' records into it instead of creating its own, which needs write access on the zone (e.g. Private DNS Zone Contributor) and the zone to be linked to this virtual network from wherever it lives. Zones left out fall back to create_private_dns_zones."
  type        = map(string)
  default     = {}
}

variable "monitor_private_dns_zone_names" {
  description = "The private DNS zones the Azure Monitor private link scope endpoint resolves through. Only used when enable_private_monitoring is true; the blob zone the agents also need is always included."
  type        = list(string)
  default = [
    "privatelink.monitor.azure.com",
    "privatelink.oms.opinsights.azure.com",
    "privatelink.ods.opinsights.azure.com",
    "privatelink.agentsvc.azure-automation.net",
  ]
}

# ------------------------------------------------------------
# Core services
# ------------------------------------------------------------

variable "enable_private_monitoring" {
  description = "Whether the workspace and Application Insights component only accept telemetry through an Azure Monitor private link scope, reached over a private endpoint on this network. Turning it off drops the scope, the data collection endpoint and their endpoint, and opens the workspace and component to ingestion over their public endpoints instead - which the virtual machine subnet's HTTPS egress rule already allows."
  type        = bool
  default     = true
}

variable "enable_monitor_agent" {
  description = "Whether the Azure Monitor Agent is installed on the virtual machines, each with its own data collection rule sending logs and core performance counters to this application's workspace."
  type        = bool
  default     = true
}

variable "log_retention_in_days" {
  description = "The number of days data is retained in the Log Analytics workspace."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_in_days >= 30 && var.log_retention_in_days <= 730
    error_message = "log_retention_in_days must be between 30 and 730."
  }
}

variable "log_daily_quota_gb" {
  description = "The workspace's daily ingestion cap in GB. Leave null for no cap."
  type        = number
  default     = null
}

variable "application_insights_retention_in_days" {
  description = "The number of days telemetry is retained in the Application Insights component."
  type        = number
  default     = 90

  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.application_insights_retention_in_days)
    error_message = "application_insights_retention_in_days must be one of 30, 60, 90, 120, 180, 270, 365, 550 or 730."
  }
}

variable "key_vault_name" {
  description = "The globally unique name of the application's key vault. Defaults to kv-<deployment_name>-<environment>."
  type        = string
  default     = null
}

variable "key_vault_secrets_officer_principal_ids" {
  description = "Principal IDs granted the Key Vault Secrets Officer role, so they can create and manage this application's secrets from inside the network, e.g. an administrators group. This stack writes no secret values itself, so nothing it deploys ends up in source control or in the state."
  type        = list(string)
  default     = []
}

variable "storage_account_name" {
  description = "The globally unique name of the application's storage account. Defaults to st<deployment_name><environment> with the hyphens removed."
  type        = string
  default     = null
}

variable "storage_replication_type" {
  description = "The replication type of the application's storage account, e.g. LRS, ZRS, GZRS."
  type        = string
  default     = "ZRS"
}

variable "storage_containers" {
  description = "Blob containers created in the application's storage account. The workloads read and write them with their managed identities: shared key authorisation is disabled."
  type        = set(string)
  default     = ["app-data"]
}

# ------------------------------------------------------------
# Virtual machines
#
# Both tiers share one subnet, one network security group and the same
# trusted launch settings; each has its own count, so an environment
# runs as many of each tier as it needs.
# ------------------------------------------------------------

variable "availability_zones" {
  description = "Availability zones the virtual machines (and their disks) are distributed across round-robin, e.g. [\"1\", \"2\", \"3\"]. Each tier is distributed independently, so a tier with fewer machines than zones still spreads across the first of them. Leave empty for a regional deployment."
  type        = list(string)
  default     = []
}

variable "secure_boot_enabled" {
  description = "Whether trusted launch secure boot is enabled on the virtual machines. The default marketplace images support trusted launch; set false alongside vtpm_enabled when a source_image_id points at a gallery image whose definition is generation 1 or was created with trusted_launch_supported = false, which Azure otherwise refuses to deploy."
  type        = bool
  default     = true
}

variable "vtpm_enabled" {
  description = "Whether the trusted launch virtual TPM is enabled on the virtual machines."
  type        = bool
  default     = true
}

variable "encryption_at_host_enabled" {
  description = "Whether encryption at host is enabled on the virtual machines. Requires the Microsoft.Compute/EncryptionAtHost feature to be registered in the deployment subscription."
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Whether to deploy a Recovery Services vault and protect both virtual machine tiers with its daily backup policy. The vault only accepts traffic through its private endpoint, so backup_private_endpoint_dns_zone_name is also required: backup traffic resolves the vault through the geo-specific backup zone alongside the blob and queue zones the backup service uses."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_backup || var.backup_private_endpoint_dns_zone_name != null
    error_message = "enable_backup requires backup_private_endpoint_dns_zone_name: the vault only accepts traffic through its private endpoint, which needs the geo-specific backup private DNS zone."
  }
}

variable "backup_private_endpoint_dns_zone_name" {
  description = "The geo-specific backup private DNS zone the vault's private endpoint resolves through, e.g. privatelink.uks.backup.windowsazure.com for UK South. The geo code is the region's, not the region name, so it has to be given rather than derived from deployment_location. Handled like every other zone this stack uses: created here, taken from existing_private_dns_zone_ids, or left to platform policy. Leave null where enable_backup is false."
  type        = string
  default     = null

  validation {
    condition     = var.backup_private_endpoint_dns_zone_name == null ? true : can(regex("^privatelink\\.[a-z0-9]+\\.backup\\.windowsazure\\.com$", var.backup_private_endpoint_dns_zone_name))
    error_message = "backup_private_endpoint_dns_zone_name must be a geo-specific backup zone, e.g. privatelink.uks.backup.windowsazure.com."
  }
}

variable "backup_storage_mode_type" {
  description = "The storage redundancy of the Recovery Services vault: LocallyRedundant, ZoneRedundant or GeoRedundant. It can only be changed while the vault protects nothing, so pick it before the first machine registers."
  type        = string
  default     = "GeoRedundant"

  validation {
    condition     = contains(["GeoRedundant", "LocallyRedundant", "ZoneRedundant"], var.backup_storage_mode_type)
    error_message = "backup_storage_mode_type must be GeoRedundant, LocallyRedundant or ZoneRedundant."
  }
}

variable "backup_daily_retention_days" {
  description = "Days the vault's daily virtual machine backups are retained."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_daily_retention_days >= 7 && var.backup_daily_retention_days <= 9999
    error_message = "backup_daily_retention_days must be between 7 and 9999."
  }
}

variable "linux_virtual_machine_role" {
  description = "The role suffix of the Linux tier, used in its machine names (vm-<deployment_name>-<environment>-<role>-<index>) and its application security group (asg-<deployment_name>-<environment>-<role>)."
  type        = string
  default     = "web"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.linux_virtual_machine_role))
    error_message = "linux_virtual_machine_role must be lowercase letters, numbers and hyphens, starting and ending alphanumeric."
  }
}

variable "linux_virtual_machine_count" {
  description = "The number of Linux web tier machines to deploy. Machine names always carry their index, so raising this adds machines without renaming - and therefore replacing - the ones already running. Set 0 to leave the tier out of an environment."
  type        = number
  default     = 1

  validation {
    condition     = var.linux_virtual_machine_count >= 0
    error_message = "linux_virtual_machine_count must be zero or more."
  }
}

variable "linux_virtual_machine_size" {
  description = "The size of the Linux web tier machines."
  type        = string
  default     = "Standard_B2s"
}

variable "linux_admin_username" {
  description = "The admin username of the Linux web tier machines."
  type        = string
  default     = "azureadmin"
}

variable "linux_admin_ssh_public_key" {
  description = "The OpenSSH public key that authenticates the admin user on the Linux machines. Password authentication is disabled, and a public key is not a secret, so it is held here rather than read from the key vault at deploy time - which is what lets this stack plan from a hosted agent. The matching private key never reaches Azure or this repository."
  type        = string

  validation {
    condition     = can(regex("^ssh-", var.linux_admin_ssh_public_key))
    error_message = "linux_admin_ssh_public_key must be an OpenSSH public key, e.g. starting with ssh-rsa or ssh-ed25519."
  }
}

variable "linux_os_disk" {
  description = "Settings of the Linux machines' operating system disks, including optional customer-managed key encryption through a disk encryption set."
  type = object({
    caching                = optional(string, "ReadWrite")
    storage_account_type   = optional(string, "StandardSSD_LRS")
    disk_size_gb           = optional(number)
    disk_encryption_set_id = optional(string)
  })
  default = {}
}

variable "linux_data_disks" {
  description = "Managed data disks created and attached to each Linux machine, in LUN order. Names are prefixed with the machine name, so each machine gets its own disks."
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

variable "linux_source_image_id" {
  description = "The ID of a compute gallery image (or image version) the Linux machines are created from, e.g. one published by the golden-image stack. Leave null for the marketplace default."
  type        = string
  default     = null
}

variable "windows_virtual_machine_role" {
  description = "The role suffix of the Windows tier, used in its machine names (vm-<deployment_name>-<environment>-<role>-<index>) and its application security group (asg-<deployment_name>-<environment>-<role>)."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.windows_virtual_machine_role))
    error_message = "windows_virtual_machine_role must be lowercase letters, numbers and hyphens, starting and ending alphanumeric."
  }
}

variable "windows_virtual_machine_count" {
  description = "The number of Windows application tier machines to deploy. Machine names always carry their index, so raising this adds machines without renaming - and therefore replacing - the ones already running. Set 0 to leave the tier out of an environment."
  type        = number
  default     = 1

  validation {
    condition     = var.windows_virtual_machine_count >= 0
    error_message = "windows_virtual_machine_count must be zero or more."
  }
}

variable "windows_virtual_machine_size" {
  description = "The size of the Windows application tier machines."
  type        = string
  default     = "Standard_B2s"
}

variable "windows_admin_username" {
  description = "The admin username of the Windows application tier machines. The password is generated per machine at deployment time and never held in source control."
  type        = string
  default     = "azureadmin"
}

variable "windows_computer_name_prefix" {
  description = "The prefix of the Windows machines' in-guest computer names, which the machine index is appended to (e.g. appsrv0). Windows limits computer names to 15 characters, far shorter than the derived resource names, so the two are deliberately separate."
  type        = string
  default     = "appsrv"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,12}$", var.windows_computer_name_prefix))
    error_message = "windows_computer_name_prefix must be at most 12 characters of letters, numbers and hyphens, leaving room for the machine index inside the 15 character Windows computer name limit."
  }
}

variable "windows_license_type" {
  description = "The existing licence applied to the Windows machines through Azure Hybrid Benefit: Windows_Server for machines covered by Software Assurance. Leave null for pay-as-you-go."
  type        = string
  default     = null
}

variable "windows_os_disk" {
  description = "Settings of the Windows machines' operating system disks, including optional customer-managed key encryption through a disk encryption set."
  type = object({
    caching                = optional(string, "ReadWrite")
    storage_account_type   = optional(string, "StandardSSD_LRS")
    disk_size_gb           = optional(number)
    disk_encryption_set_id = optional(string)
  })
  default = {}
}

variable "windows_data_disks" {
  description = "Managed data disks created and attached to each Windows machine, in LUN order. Names are prefixed with the machine name, so each machine gets its own disks."
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

variable "windows_source_image_id" {
  description = "The ID of a compute gallery image (or image version) the Windows machines are created from, e.g. one published by the golden-image stack. Leave null for the marketplace default."
  type        = string
  default     = null
}

# ------------------------------------------------------------
# Azure SQL
# ------------------------------------------------------------

variable "sql_server_count" {
  description = "The number of SQL servers to deploy, each carrying the databases named in sql_databases and its own private endpoint. Server names always carry their index, so raising this adds servers without renaming the ones already deployed. Set 0 to leave SQL out of an environment."
  type        = number
  default     = 1

  validation {
    condition     = var.sql_server_count >= 0
    error_message = "sql_server_count must be zero or more."
  }
}

variable "sql_server_name_prefix" {
  description = "The prefix of the SQL server names, which the server index is appended to. Server names are globally unique as they form the default hostname, so override this where sql-<deployment_name>-<environment> is taken. Defaults to sql-<deployment_name>-<environment>."
  type        = string
  default     = null
}

variable "sql_entra_admin_login_username" {
  description = "The login name of the SQL servers' Microsoft Entra ID administrator, e.g. a database administrators group. Entra ID authentication is the only authentication the servers accept, so there are no SQL logins to store or rotate."
  type        = string
}

variable "sql_entra_admin_object_id" {
  description = "The object ID of the SQL servers' Microsoft Entra ID administrator."
  type        = string
}

variable "sql_databases" {
  description = "The databases created on every SQL server, keyed by name. auto_pause_delay_in_minutes only applies to serverless SKUs (which pause when idle); leave it null on provisioned SKUs."
  type = map(object({
    sku_name                    = optional(string, "GP_S_Gen5_1")
    max_size_gb                 = optional(number, 32)
    zone_redundant              = optional(bool, false)
    auto_pause_delay_in_minutes = optional(number)
  }))
  default = {
    appdb = {
      sku_name                    = "GP_S_Gen5_1"
      max_size_gb                 = 32
      auto_pause_delay_in_minutes = 60
    }
  }
}

# ------------------------------------------------------------
# Web app
# ------------------------------------------------------------

variable "enable_app_service" {
  description = "Whether to deploy the web app and its App Service plan into the delegated App Service subnet. The subnet itself is always created, so turning this off leaves the network shape unchanged and the subnet ready for the app."
  type        = bool
  default     = true
}

variable "web_app_name" {
  description = "The globally unique name of the web app, which forms its default hostname. Defaults to app-<deployment_name>-<environment>."
  type        = string
  default     = null
}

variable "app_service_sku" {
  description = "The SKU of the App Service plan, e.g. B1, S1, P1v3."
  type        = string
  default     = "P1v3"
}

variable "app_service_worker_count" {
  description = "The number of workers in the App Service plan."
  type        = number
  default     = 1
}

variable "app_service_zone_balancing_enabled" {
  description = "Whether App Service plan instances spread across availability zones. Requires a Premium SKU and at least two workers."
  type        = bool
  default     = false
}

variable "app_service_application_stack" {
  description = "The web app's runtime stack, e.g. { node_version = \"20-lts\" } or { dotnet_version = \"8.0\" }."
  type        = map(string)
  default = {
    dotnet_version = "8.0"
  }
}

variable "app_service_app_settings" {
  description = "Additional application settings for the web app, merged over the settings the stack derives (the Application Insights connection string, the key vault URI, the blob endpoint and one SQL_SERVER_<index>_FQDN per server)."
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

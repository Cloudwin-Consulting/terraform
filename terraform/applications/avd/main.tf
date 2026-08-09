locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  # The upstream stacks this one looks up derive their names the
  # same way, from their own workload name and this environment.
  app_spoke_network_resource_group_name = "rg-${var.app_spoke_deployment_name}-${var.environment}-network"
  app_spoke_virtual_network_name        = "vnet-${var.app_spoke_deployment_name}-${var.environment}"
  application_security_group_name       = var.application_security_group_role == null ? null : "asg-${var.app_spoke_deployment_name}-${var.environment}-${var.application_security_group_role}"
  hub_dns_resource_group_name           = "rg-${var.hub_deployment_name}-${var.environment}-dns"
  log_analytics_workspace_name          = "log-${var.monitoring_deployment_name}-${var.environment}"
  monitoring_resource_group_name        = "rg-${var.monitoring_deployment_name}-${var.environment}"
  data_collection_endpoint_name         = coalesce(var.data_collection_endpoint_name, "dce-${var.monitoring_deployment_name}-${var.environment}")


  resource_group_name    = "rg-${local.name_suffix}"
  host_pool_name         = "vdpool-${local.name_suffix}"
  application_group_name = "vdag-${local.name_suffix}"
  workspace_name         = "vdws-${local.name_suffix}"
  scaling_plan_name      = "vdscaling-${local.name_suffix}"

  session_host_names = [
    for i in range(var.session_host_count) : "vm-${local.name_suffix}-${i}"
  ]

  fslogix_storage_account_name = coalesce(var.fslogix_storage_account_name, "st${replace(local.name_suffix, "-", "")}fsl")
  fslogix_profile_share_name   = "profiles"

  # The Environment tag holds the standard name of the environment,
  # while var.environment keeps the short form every resource name is
  # derived from - so the tag standard renames nothing.
  standard_environment_tags = {
    rd   = "RD"
    dev  = "Development"
    qa   = "QA"
    prod = "Production"
  }

  # The optional tags only join the set once they have a value, so no
  # resource carries an empty ExpiryDate, BusinessUnit or Repository.
  optional_tags = merge(
    var.expiry_date != null ? { ExpiryDate = var.expiry_date } : {},
    var.business_unit != null ? { BusinessUnit = var.business_unit } : {},
    var.repository != null ? { Repository = var.repository } : {},
  )

  # The tag set every resource in this stack carries: set on the
  # resources declared here and passed to every shared module, so
  # each resource is tagged in its own right rather than relying on
  # resource group tag inheritance. var.tags is merged last, so a
  # deployment can add to - or override - the standard values.
  common_tags = merge(
    {
      Application        = coalesce(var.application, var.deployment_name)
      Environment        = coalesce(var.environment_tag, lookup(local.standard_environment_tags, lower(var.environment), null))
      Owner              = var.owner
      CostCenter         = coalesce(var.cost_center, var.application, var.deployment_name)
      ManagedBy          = "Terraform"
      Criticality        = var.criticality
      Service            = var.service
      DataClassification = var.data_classification
      Lifecycle          = var.lifecycle_stage
    },
    local.optional_tags,
    var.tags,
  )
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.deployment_location
  tags     = local.common_tags
}

# ------------------------------------------------------------
# Existing platform resources: the application spoke network, the
# hub's private DNS zones and the monitoring workspace.
# ------------------------------------------------------------

data "azurerm_subnet" "session_hosts" {
  provider = azurerm.app_spoke

  name                 = var.session_host_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

data "azurerm_subnet" "private_endpoints" {
  provider = azurerm.app_spoke

  count = var.enable_fslogix ? 1 : 0

  name                 = var.private_endpoint_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

data "azurerm_private_dns_zone" "file" {
  provider = azurerm.hub

  count = var.enable_fslogix ? 1 : 0

  name                = "privatelink.file.core.windows.net"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_application_security_group" "this" {
  provider = azurerm.app_spoke

  count = local.application_security_group_name == null ? 0 : 1

  name                = local.application_security_group_name
  resource_group_name = local.app_spoke_network_resource_group_name
}

data "azurerm_log_analytics_workspace" "monitoring" {
  provider = azurerm.monitoring

  name                = local.log_analytics_workspace_name
  resource_group_name = local.monitoring_resource_group_name
}

data "azurerm_monitor_data_collection_endpoint" "monitoring" {
  provider = azurerm.monitoring

  count = var.enable_monitor_agent ? 1 : 0

  name                = local.data_collection_endpoint_name
  resource_group_name = local.monitoring_resource_group_name
}

# ------------------------------------------------------------
# The Azure Virtual Desktop control plane objects: the host pool the
# session hosts register into, the desktop application group users are
# entitled to, and the workspace the AVD clients subscribe to. All
# connectivity uses the service's reverse connect transport - session
# hosts and clients dial out over HTTPS, so nothing in the spoke
# listens for inbound connections - and the AVD logs flow to the
# monitoring workspace, where AVD Insights reads them.
# ------------------------------------------------------------

module "host_pool" {
  source = "../../shared/avd-host-pool"

  name                = local.host_pool_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  friendly_name       = var.host_pool_friendly_name
  tags                = local.common_tags

  type                     = var.host_pool_type
  load_balancer_type       = var.host_pool_load_balancer_type
  maximum_sessions_allowed = var.maximum_sessions_allowed
  start_vm_on_connect      = var.start_vm_on_connect
  validate_environment     = var.validate_environment
  custom_rdp_properties    = var.custom_rdp_properties

  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.monitoring.id
}

module "desktop_application_group" {
  source = "../../shared/avd-application-group"

  name                = local.application_group_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags

  type                         = "Desktop"
  host_pool_id                 = module.host_pool.id
  friendly_name                = var.desktop_friendly_name
  default_desktop_display_name = var.desktop_friendly_name

  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.monitoring.id
}

module "workspace" {
  source = "../../shared/avd-workspace"

  name                = local.workspace_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  friendly_name       = var.workspace_friendly_name
  tags                = local.common_tags

  application_group_ids = {
    desktop = module.desktop_application_group.id
  }

  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.monitoring.id
}

# ------------------------------------------------------------
# Session hosts: Windows 11 multi-session machines joined to Microsoft
# Entra ID and registered into the host pool. The local admin account
# is break-glass only and its password is generated at deployment time
# (state only, never in source control; retrieve with
# `terraform output -json session_host_admin_passwords`): users sign
# in with their Entra credentials through the Virtual Machine User
# Login role granted below. Scale out with session_host_count.
# ------------------------------------------------------------

resource "random_password" "session_host_admin" {
  count = var.session_host_count

  length      = 24
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  min_special = 1
}

# The AVD Insights data collection rule the session hosts share: the
# session host event channels (Terminal Services, FSLogix, System,
# Application) and the session, input delay, network and core machine
# counters the AVD Insights workbooks read, delivered to the
# monitoring workspace through its data collection endpoint. The
# agent module associates this rule instead of creating its generic
# default, which collects none of the AVD-specific data.
resource "azurerm_monitor_data_collection_rule" "avd_insights" {
  count = var.enable_monitor_agent ? 1 : 0

  name                        = "dcr-${local.name_suffix}"
  resource_group_name         = azurerm_resource_group.this.name
  location                    = azurerm_resource_group.this.location
  kind                        = "Windows"
  data_collection_endpoint_id = data.azurerm_monitor_data_collection_endpoint.monitoring[0].id
  tags                        = local.common_tags

  destinations {
    log_analytics {
      workspace_resource_id = data.azurerm_log_analytics_workspace.monitoring.id
      name                  = "log-analytics"
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Event"]
    destinations = ["log-analytics"]
  }

  data_sources {
    performance_counter {
      name                          = "avd-counters-30s"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 30
      counter_specifiers = [
        "\\LogicalDisk(C:)\\Avg. Disk Queue Length",
        "\\LogicalDisk(C:)\\Current Disk Queue Length",
        "\\Memory\\Available Mbytes",
        "\\Memory\\Page Faults/sec",
        "\\Memory\\Pages/sec",
        "\\Memory\\% Committed Bytes In Use",
        "\\PhysicalDisk(*)\\Avg. Disk Queue Length",
        "\\PhysicalDisk(*)\\Avg. Disk sec/Read",
        "\\PhysicalDisk(*)\\Avg. Disk sec/Transfer",
        "\\PhysicalDisk(*)\\Avg. Disk sec/Write",
        "\\Processor Information(_Total)\\% Processor Time",
        "\\User Input Delay per Process(*)\\Max Input Delay",
        "\\User Input Delay per Session(*)\\Max Input Delay",
        "\\RemoteFX Network(*)\\Current TCP RTT",
        "\\RemoteFX Network(*)\\Current UDP Bandwidth",
      ]
    }

    performance_counter {
      name                          = "avd-counters-60s"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\LogicalDisk(C:)\\% Free Space",
        "\\LogicalDisk(C:)\\Avg. Disk sec/Transfer",
        "\\Terminal Services(*)\\Active Sessions",
        "\\Terminal Services(*)\\Inactive Sessions",
        "\\Terminal Services(*)\\Total Sessions",
      ]
    }

    windows_event_log {
      name    = "avd-events"
      streams = ["Microsoft-Event"]
      # Level 1 is Critical, 2 Error, 3 Warning, 4 Information and 0
      # LogAlways - so every query starts at Critical, and the session
      # host channels also carry the informational connection events
      # AVD Insights reports on.
      x_path_queries = [
        "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]",
        "Microsoft-Windows-TerminalServices-RemoteConnectionManager/Admin!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]",
        "Microsoft-FSLogix-Apps/Operational!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]",
        "Microsoft-FSLogix-Apps/Admin!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]",
        "System!*[System[(Level=1 or Level=2 or Level=3)]]",
        "Application!*[System[(Level=1 or Level=2 or Level=3)]]",
      ]
    }
  }
}

module "session_host" {
  source = "../../shared/avd-session-host"

  count = var.session_host_count

  name                = local.session_host_names[count.index]
  computer_name       = "${var.computer_name_prefix}${count.index}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = data.azurerm_subnet.session_hosts.id
  size                = var.session_host_size
  admin_password      = random_password.session_host_admin[count.index].result
  tags                = local.common_tags

  host_pool_name     = module.host_pool.name
  host_pool_id       = module.host_pool.id
  registration_token = module.host_pool.registration_token

  application_security_group_ids = local.application_security_group_name == null ? [] : [data.azurerm_application_security_group.this[0].id]

  # Session hosts are distributed round-robin across the availability
  # zones.
  zone = length(var.availability_zones) > 0 ? var.availability_zones[count.index % length(var.availability_zones)] : null

  os_disk                    = var.os_disk
  source_image_id            = var.source_image_id
  source_image_reference     = var.source_image_reference
  license_type               = var.license_type
  encryption_at_host_enabled = var.encryption_at_host_enabled

  # The shared AVD Insights rule is created in this apply, so its
  # unknown ID cannot decide the agent module's default-rule count -
  # create_data_collection_rule is pinned off explicitly.
  monitor_agent = var.enable_monitor_agent ? {
    data_collection_rule_id     = azurerm_monitor_data_collection_rule.avd_insights[0].id
    data_collection_endpoint_id = data.azurerm_monitor_data_collection_endpoint.monitoring[0].id
    create_data_collection_rule = false
  } : null
}

# ------------------------------------------------------------
# User entitlements. AVD authorises users with Azure RBAC: Desktop
# Virtualization User on the application group shows them the desktop
# in their feed, and Virtual Machine User Login lets them sign in to
# the Entra joined session hosts. Set avd_users_group_object_id to a
# Microsoft Entra ID group holding the desktop's users.
# ------------------------------------------------------------

module "avd_users_desktop" {
  source = "../../shared/rbac-role-assignment"

  count = var.avd_users_group_object_id == null ? 0 : 1

  scope                = module.desktop_application_group.id
  role_definition_name = "Desktop Virtualization User"
  principals           = { avd-users = var.avd_users_group_object_id }
  principal_type       = "Group"
  description          = "Entitles the AVD users group to the published desktop."
}

module "avd_users_vm_login" {
  source = "../../shared/rbac-role-assignment"

  count = var.avd_users_group_object_id == null ? 0 : 1

  scope                = azurerm_resource_group.this.id
  role_definition_name = "Virtual Machine User Login"
  principals           = { avd-users = var.avd_users_group_object_id }
  principal_type       = "Group"
  description          = "Lets the AVD users group sign in to the Entra joined session hosts."
}

# ------------------------------------------------------------
# Scaling plan (optional): starts and deallocates session hosts on a
# working-week schedule so capacity follows demand. The Azure Virtual
# Desktop service principal must first be granted the power management
# role on the session hosts' resource group - it also powers on
# stopped hosts when start_vm_on_connect is enabled - so
# avd_service_principal_object_id is required for either feature.
# ------------------------------------------------------------

module "avd_service_principal_power" {
  source = "../../shared/rbac-role-assignment"

  count = var.avd_service_principal_object_id == null ? 0 : 1

  scope                = azurerm_resource_group.this.id
  role_definition_name = "Desktop Virtualization Power On Off Contributor"
  principals           = { azure-virtual-desktop = var.avd_service_principal_object_id }
  principal_type       = "ServicePrincipal"
  description          = "Lets the Azure Virtual Desktop service start and deallocate the session hosts for the scaling plan and start VM on connect."
}

module "scaling_plan" {
  source = "../../shared/avd-scaling-plan"

  count = var.enable_scaling_plan ? 1 : 0

  # The plan cannot manage the session hosts until the AVD service
  # principal holds the power management role.
  depends_on = [module.avd_service_principal_power]

  name                = local.scaling_plan_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags

  time_zone = var.scaling_plan_time_zone
  schedules = var.scaling_plan_schedules

  host_pools = {
    avd = { host_pool_id = module.host_pool.id }
  }
}

# ------------------------------------------------------------
# FSLogix profile storage (optional): user profiles roam between the
# pooled session hosts as containers on an Azure file share, reached
# over its private endpoint and authenticated with Microsoft Entra
# Kerberos (AADKERB) - no domain controllers involved. The repository's
# configure-fslogix.ps1 points each host at the share through the Run
# Command service. Two follow-ups happen once, outside Terraform: an
# administrator grants admin consent to the storage account's
# auto-created Entra application (Azure portal, the account's File
# shares blade), and users' sessions pick the profile up at next
# sign-in.
# ------------------------------------------------------------

module "fslogix_storage" {
  source = "../../shared/storage-account"

  count = var.enable_fslogix ? 1 : 0

  name                = local.fslogix_storage_account_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags

  account_replication_type = var.fslogix_storage_replication_type

  file_shares = {
    (local.fslogix_profile_share_name) = {
      quota_in_gb = var.fslogix_profiles_share_quota_gb
    }
  }

  azure_files_authentication = {
    directory_type = "AADKERB"
  }

  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.monitoring.id
}

module "fslogix_private_endpoint" {
  source = "../../shared/private-endpoint"

  count = var.enable_fslogix ? 1 : 0

  name                           = "pep-file-${local.fslogix_storage_account_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints[0].id
  private_connection_resource_id = module.fslogix_storage[0].id
  subresource_names              = ["file"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.file[0].id]
  tags                           = local.common_tags
}

# Users read and write their own profile containers on the share.
# Azure Files' default root ACLs already allow this at the NTFS level
# (authenticated users hold modify, and CREATOR OWNER gives each user
# full control of the container they create), so no ACL work is
# needed before first sign-in.
module "avd_users_fslogix_share" {
  source = "../../shared/rbac-role-assignment"

  count = var.enable_fslogix && var.avd_users_group_object_id != null ? 1 : 0

  scope                = module.fslogix_storage[0].id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principals           = { avd-users = var.avd_users_group_object_id }
  principal_type       = "Group"
  description          = "Lets the AVD users group read and write their FSLogix profile containers."
}

# Administrators mount the share with full control to manage its NTFS
# ACLs over SMB - e.g. applying the recommended FSLogix hardening that
# stops users browsing each other's containers. The account disables
# shared key access, so this role is the only elevated path to the
# ACLs.
module "fslogix_share_admins" {
  source = "../../shared/rbac-role-assignment"

  count = var.enable_fslogix && var.fslogix_admins_group_object_id != null ? 1 : 0

  scope                = module.fslogix_storage[0].id
  role_definition_name = "Storage File Data SMB Share Elevated Contributor"
  principals           = { fslogix-admins = var.fslogix_admins_group_object_id }
  principal_type       = "Group"
  description          = "Lets the FSLogix administrators group manage the profile share's NTFS ACLs."
}

# Reconciles each session host's FSLogix configuration with this
# stack's, through the Run Command service: with FSLogix enabled it
# points the agent at the profile share and enables Entra Kerberos
# ticket retrieval; with FSLogix disabled it passes an empty path,
# which turns profiles off in the guest.
#
# The run command therefore deploys for every session host, not only
# when FSLogix is on. Deleting a run command does not undo what its
# script wrote, so a conditional one would leave a host that had
# FSLogix enabled pointed at the share this apply destroys - users
# would fail to attach a profile until someone cleaned up by hand.
# The share path is not a secret, so it travels as a plain parameter.
module "configure_fslogix" {
  source = "../../shared/virtual-machine-run-command"

  count = var.session_host_count

  name               = "configure-fslogix"
  virtual_machine_id = module.session_host[count.index].id
  location           = azurerm_resource_group.this.location
  tags               = local.common_tags

  script_content = file("${path.module}/scripts/configure-fslogix.ps1")

  parameters = {
    ProfileShareUncPath = var.enable_fslogix ? "\\\\${local.fslogix_storage_account_name}.file.core.windows.net\\${local.fslogix_profile_share_name}" : ""
  }
}

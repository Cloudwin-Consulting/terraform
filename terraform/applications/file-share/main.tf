locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  # The upstream stacks this one looks up derive their names the
  # same way, from their own workload name and this environment.
  app_spoke_network_resource_group_name = "rg-${var.app_spoke_deployment_name}-${var.environment}-network"
  app_spoke_virtual_network_name        = "vnet-${var.app_spoke_deployment_name}-${var.environment}"
  application_security_group_name       = var.application_security_group_role == null ? null : "asg-${var.app_spoke_deployment_name}-${var.environment}-${var.application_security_group_role}"

  hub_dns_resource_group_name    = "rg-${var.hub_deployment_name}-${var.environment}-dns"
  log_analytics_workspace_name   = "log-${var.monitoring_deployment_name}-${var.environment}"
  monitoring_resource_group_name = "rg-${var.monitoring_deployment_name}-${var.environment}"
  data_collection_endpoint_name  = coalesce(var.data_collection_endpoint_name, "dce-${var.monitoring_deployment_name}-${var.environment}")

  platform_key_vault_name                = "kv-${var.app_spoke_deployment_name}-${var.environment}"
  platform_key_vault_resource_group_name = "rg-${var.app_spoke_deployment_name}-${var.environment}-secrets"

  resource_group_name  = "rg-${local.name_suffix}"
  storage_account_name = coalesce(var.storage_account_name, "st${replace(local.name_suffix, "-", "")}")
  vm_name              = "vm-${local.name_suffix}"

  vm_names = [
    for i in range(var.virtual_machine_count) :
    var.virtual_machine_count == 1 ? local.vm_name : "${local.vm_name}-${i}"
  ]

  # Shared key authorisation is only enabled for the mount that needs
  # it: with identity-based authentication configured the machines
  # authenticate as their own directory identities, so the account
  # keeps the module's default of no shared key access at all.
  shared_access_key_enabled = var.azure_files_authentication == null

  # The host the machines mount the share from, taken from the
  # account's own file endpoint rather than assembled from a hard-coded
  # suffix, so the UNC path follows whatever the account reports. It
  # resolves to the private endpoint's address through the hub's file
  # zone, which - like every other zone this repository's stacks look
  # up - is named for the public cloud.
  file_endpoint_host = trimsuffix(replace(module.storage_account.primary_file_endpoint, "https://", ""), "/")

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

# A share-only deployment (virtual_machine_count = 0) needs nothing
# from the virtual machine subnet, so it is not looked up: a spoke
# that never turned that subnet on still deploys the share.
data "azurerm_subnet" "virtual_machines" {
  provider = azurerm.app_spoke

  count = var.virtual_machine_count > 0 ? 1 : 0

  name                 = var.virtual_machine_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

data "azurerm_subnet" "private_endpoints" {
  provider = azurerm.app_spoke

  name                 = var.private_endpoint_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

data "azurerm_private_dns_zone" "file" {
  provider = azurerm.hub

  name                = "privatelink.file.core.windows.net"
  resource_group_name = local.hub_dns_resource_group_name
}

# Only the machines join an ASG, so this is looked up alongside them.
data "azurerm_application_security_group" "this" {
  provider = azurerm.app_spoke

  count = local.application_security_group_name == null || var.virtual_machine_count == 0 ? 0 : 1

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
# Application file storage: a storage account holding one SMB file
# share, reached over SMB through its private endpoint alone - the
# account's public endpoint is off and its network rules deny
# everything else. The share is where the Windows machines below save
# the application's files, so the data outlives any one machine:
# rebuilding, scaling out or resizing a machine leaves the files
# where they are, and every machine sees the same set.
#
# The share is created through the management plane by the shared
# storage-account module, so no data plane access is needed at
# deployment time. Its quota is the billed maximum for a standard
# account, not a reservation.
# ------------------------------------------------------------

module "storage_account" {
  source = "../../shared/storage-account"

  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags

  account_replication_type = var.storage_account_replication_type

  file_shares = {
    (var.file_share_name) = {
      quota_in_gb = var.file_share_quota_gb
      access_tier = var.file_share_access_tier
    }
  }

  # Identity-based authentication (Active Directory or Microsoft Entra
  # Kerberos) when the environment has a directory the machines are
  # joined to, otherwise the machines mount with the account key that
  # shared_access_key_enabled keeps available for them.
  azure_files_authentication = var.azure_files_authentication
  shared_access_key_enabled  = local.shared_access_key_enabled

  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.monitoring.id
}

module "file_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-file-${local.storage_account_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.storage_account.id
  subresource_names              = ["file"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.file.id]
  tags                           = local.common_tags
}

# Share-level permissions for the identities that read and write the
# application's files over SMB - the service accounts an application
# runs as, or the group its operators belong to. They only apply with
# identity-based authentication configured: a machine mounting with
# the account key is authorised by the key alone, and holds full
# access to the share.
module "share_contributors" {
  source = "../../shared/rbac-role-assignment"

  count = length(var.share_contributor_principals) > 0 ? 1 : 0

  scope                = module.storage_account.id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principals           = var.share_contributor_principals
  principal_type       = var.share_principal_type
  description          = "Lets the application's identities read and write files on the ${var.file_share_name} share."
}

# Administrators mount the share with full control to manage its NTFS
# ACLs over SMB - the directory layout an application expects, and the
# permissions on it. With shared key access disabled this role is the
# only elevated path to those ACLs.
module "share_admins" {
  source = "../../shared/rbac-role-assignment"

  count = length(var.share_admin_principals) > 0 ? 1 : 0

  scope                = module.storage_account.id
  role_definition_name = "Storage File Data SMB Share Elevated Contributor"
  principals           = var.share_admin_principals
  principal_type       = var.share_principal_type
  description          = "Lets the application's administrators manage the ${var.file_share_name} share's NTFS ACLs."
}

# ------------------------------------------------------------
# Windows Server virtual machines mounting the share
#
# The machines have no public IP addresses and only accept RDP from
# Azure Bastion in the hub, enforced by the spoke's network security
# group. The admin password is never committed to source control: it
# is read from a secret pre-loaded into the spoke's platform key vault
# when admin_password_key_vault_secret is set, otherwise each machine
# gets its own password generated at deployment time (retrieve with
# `terraform output -json virtual_machine_admin_passwords` or rotate
# with `az vm user update`).
#
# Set virtual_machine_count = 0 to deploy the share on its own, for
# application files written by machines another stack owns - they
# mount it the same way, from the same UNC path.
# ------------------------------------------------------------

data "azurerm_key_vault" "platform" {
  provider = azurerm.key_vault

  count = var.admin_password_key_vault_secret == null ? 0 : 1

  name                = coalesce(var.admin_password_key_vault_secret.key_vault_name, local.platform_key_vault_name)
  resource_group_name = coalesce(var.admin_password_key_vault_secret.key_vault_resource_group_name, local.platform_key_vault_resource_group_name)
}

# Reading the secret happens over the vault's private data plane, so
# the deployment agent must run inside the network (e.g. self-hosted).
data "azurerm_key_vault_secret" "admin_password" {
  provider = azurerm.key_vault

  count = var.admin_password_key_vault_secret == null ? 0 : 1

  name         = var.admin_password_key_vault_secret.secret_name
  key_vault_id = data.azurerm_key_vault.platform[0].id
}

resource "random_password" "admin" {
  count = var.admin_password_key_vault_secret == null ? var.virtual_machine_count : 0

  length      = 24
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  min_special = 1
}

module "virtual_machine" {
  source = "../../shared/windows-virtual-machine"

  count = var.virtual_machine_count

  name                       = local.vm_names[count.index]
  computer_name              = var.virtual_machine_count == 1 ? var.computer_name : "${var.computer_name}${count.index}"
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  subnet_id                  = data.azurerm_subnet.virtual_machines[0].id
  size                       = var.virtual_machine_size
  admin_password             = var.admin_password_key_vault_secret == null ? random_password.admin[count.index].result : data.azurerm_key_vault_secret.admin_password[0].value
  secure_boot_enabled        = var.secure_boot_enabled
  vtpm_enabled               = var.vtpm_enabled
  encryption_at_host_enabled = var.encryption_at_host_enabled
  tags                       = local.common_tags

  application_security_group_ids = local.application_security_group_name == null ? [] : [data.azurerm_application_security_group.this[0].id]

  # Machines are distributed round-robin across the availability zones.
  zone = length(var.availability_zones) > 0 ? var.availability_zones[count.index % length(var.availability_zones)] : null

  os_disk = var.os_disk

  source_image_id = var.source_image_id

  monitor_agent = var.enable_monitor_agent ? {
    log_analytics_workspace_id  = data.azurerm_log_analytics_workspace.monitoring.id
    data_collection_endpoint_id = data.azurerm_monitor_data_collection_endpoint.monitoring[0].id
  } : null
}

# ------------------------------------------------------------
# Active Directory domain join (optional)
#
# Runs the repository's join-domain.ps1 on each machine through the Run
# Command service. The script fetches the join account's credentials
# from the spoke's platform key vault at runtime with the machine's
# managed identity (granted Key Vault Secrets User below), so the
# secret values never pass through Terraform or its state - the
# deployment only handles the vault and secret names.
#
# Domain joining is what makes identity-based authentication usable
# here: a domain-joined machine mounts the share as its own directory
# identity, so no account key is involved anywhere.
# ------------------------------------------------------------

data "azurerm_key_vault" "domain_join" {
  provider = azurerm.key_vault

  count = var.domain_join == null ? 0 : 1

  name                = coalesce(var.domain_join.key_vault_name, local.platform_key_vault_name)
  resource_group_name = coalesce(var.domain_join.key_vault_resource_group_name, local.platform_key_vault_resource_group_name)
}

# Lets each machine's system-assigned identity read the join secrets
# over the vault's private endpoint.
resource "azurerm_role_assignment" "domain_join_secrets" {
  count = var.domain_join == null ? 0 : var.virtual_machine_count

  scope                = data.azurerm_key_vault.domain_join[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.virtual_machine[count.index].principal_id
}

module "domain_join" {
  source = "../../shared/virtual-machine-run-command"

  count = var.domain_join == null ? 0 : var.virtual_machine_count

  name               = "join-domain"
  virtual_machine_id = module.virtual_machine[count.index].id
  location           = azurerm_resource_group.this.location
  tags               = local.common_tags

  script_content = file("${path.module}/scripts/join-domain.ps1")

  parameters = merge(
    {
      DomainName         = var.domain_join.domain_name
      VaultName          = coalesce(var.domain_join.key_vault_name, local.platform_key_vault_name)
      UsernameSecretName = var.domain_join.username_secret_name
      PasswordSecretName = var.domain_join.password_secret_name
    },
    var.domain_join.ou_path == null ? {} : { OUPath = var.domain_join.ou_path }
  )

  depends_on = [azurerm_role_assignment.domain_join_secrets]
}

# ------------------------------------------------------------
# Mounting the share on the machines
#
# The repository's mount-file-share.ps1 maps the share to a drive
# letter through the Run Command service, as an SMB global mapping:
# machine-wide and persistent, so the drive is there for services and
# scheduled tasks - not only for the user who happened to run the
# script - and survives a restart.
#
# How the mount authenticates follows the account's configuration.
# With identity-based authentication the machine mounts as its own
# directory identity and no secret is involved. Without it the account
# key travels to the machine as an encrypted protected parameter,
# which the Run Command service never returns in instance view or
# logs; the key is in the Terraform state either way, which is why
# this stack's pipeline publishes no decodable plan artifacts.
#
# The mount waits on the private endpoint: until it exists, the
# account's host name has nothing to resolve to inside the network.
# ------------------------------------------------------------

module "mount_file_share" {
  source = "../../shared/virtual-machine-run-command"

  count = var.virtual_machine_count

  name               = "mount-file-share"
  virtual_machine_id = module.virtual_machine[count.index].id
  location           = azurerm_resource_group.this.location
  tags               = local.common_tags

  script_content = file("${path.module}/scripts/mount-file-share.ps1")

  parameters = {
    StorageAccountName = local.storage_account_name
    FileEndpointHost   = local.file_endpoint_host
    ShareName          = var.file_share_name
    DriveLetter        = var.file_share_drive_letter
  }

  # Only sent when the machines authenticate with the account key.
  # Identity-based mounts carry no secret at all.
  protected_parameters = local.shared_access_key_enabled ? {
    StorageAccountKey = module.storage_account.primary_access_key
  } : {}

  depends_on = [
    module.file_private_endpoint,
    module.domain_join,
    module.share_contributors,
  ]
}

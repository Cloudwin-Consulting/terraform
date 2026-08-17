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

  resource_group_name = "rg-${local.name_suffix}"
  vm_name             = "vm-${local.name_suffix}"
  key_vault_name      = coalesce(var.key_vault_name, "kv-${local.name_suffix}")

  vm_names = [
    for i in range(var.virtual_machine_count) :
    var.virtual_machine_count == 1 ? local.vm_name : "${local.vm_name}-${i}"
  ]

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

data "azurerm_subnet" "database" {
  provider = azurerm.app_spoke

  name                 = var.database_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

data "azurerm_subnet" "private_endpoints" {
  provider = azurerm.app_spoke

  name                 = var.private_endpoint_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

data "azurerm_private_dns_zone" "key_vault" {
  provider = azurerm.hub

  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = local.hub_dns_resource_group_name
}

# The database tier's application security group. The spoke's subnet
# NSG allows SQL traffic to this group from the application tier only,
# so the machines are reachable by the workloads that need them rather
# than by everything on the network.
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
# SQL Server on Windows Server virtual machines
#
# The machines have no public IP addresses, and SQL Server only
# listens inside the virtual network - never on the internet. The
# local administrator password is never committed to source control:
# it is read from a secret pre-loaded into the spoke's platform key
# vault when admin_password_key_vault_secret is set, otherwise each
# machine gets its own password generated at deployment time
# (retrieve with `terraform output -json virtual_machine_admin_passwords`).
#
# Authentication is Windows-only by default. Domain join the machines
# and grant access to domain groups, or set enable_sql_authentication
# for workloads whose clients cannot use Windows authentication.
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

# The SQL authentication login's password, generated per machine when
# mixed mode authentication is switched on.
resource "random_password" "sql_login" {
  count = var.enable_sql_authentication ? var.virtual_machine_count : 0

  length      = 24
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  min_special = 1
}

module "sql_server_virtual_machine" {
  source = "../../shared/sql-server-virtual-machine"

  count = var.virtual_machine_count

  # Recovery Services only accepts a private endpoint while the vault
  # has no registered backup items, so the machines (and their backup
  # registrations) wait for the endpoint.
  depends_on = [module.recovery_vault_private_endpoint]

  name                = local.vm_names[count.index]
  computer_name       = var.virtual_machine_count == 1 ? var.computer_name : "${var.computer_name}${count.index}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = data.azurerm_subnet.database.id
  size                = var.virtual_machine_size
  admin_password      = var.admin_password_key_vault_secret == null ? random_password.admin[count.index].result : data.azurerm_key_vault_secret.admin_password[0].value
  tags                = local.common_tags

  secure_boot_enabled        = var.secure_boot_enabled
  vtpm_enabled               = var.vtpm_enabled
  encryption_at_host_enabled = var.encryption_at_host_enabled
  license_type               = var.license_type

  application_security_group_ids = local.application_security_group_name == null ? [] : [data.azurerm_application_security_group.this[0].id]

  # Machines are distributed round-robin across the availability zones.
  zone = length(var.availability_zones) > 0 ? var.availability_zones[count.index % length(var.availability_zones)] : null

  os_disk = var.os_disk

  # Data, log and tempdb volumes. The disk names are prefixed with the
  # machine name so each machine's disks are distinguishable in the
  # resource group.
  data_disks = [
    for disk in var.data_disks : merge(disk, {
      name = "${local.vm_names[count.index]}-${disk.name}"
    })
  ]

  storage_configuration = var.storage_configuration

  # The marketplace image is ignored when source_image_id points at a
  # gallery image, so it is always passed rather than conditionally.
  source_image_id = var.source_image_id
  source_image_reference = {
    publisher = "MicrosoftSQLServer"
    offer     = var.sql_image_offer
    sku       = var.sql_image_sku
    version   = var.sql_image_version
  }

  sql_license_type      = var.sql_license_type
  sql_connectivity_type = var.sql_connectivity_type
  sql_connectivity_port = var.sql_connectivity_port
  r_services_enabled    = var.r_services_enabled
  sql_instance          = var.sql_instance
  auto_patching         = var.auto_patching

  sql_login = var.enable_sql_authentication ? {
    username = var.sql_login_username
    password = random_password.sql_login[count.index].result
  } : null

  # The best practices assessment reports into the same workspace the
  # monitor agent sends to, so it is only offered alongside the agent.
  assessment = var.enable_assessment ? {
    enabled  = true
    schedule = var.assessment_schedule
  } : null

  backup = var.enable_backup ? {
    recovery_vault_name                = module.recovery_services_vault[0].name
    recovery_vault_resource_group_name = azurerm_resource_group.this.name
    backup_policy_id                   = module.recovery_services_vault[0].daily_backup_policy_id
  } : null

  monitor_agent = var.enable_monitor_agent ? {
    log_analytics_workspace_id  = data.azurerm_log_analytics_workspace.monitoring.id
    data_collection_endpoint_id = data.azurerm_monitor_data_collection_endpoint.monitoring[0].id
  } : null
}

# ------------------------------------------------------------
# Recovery Services vault (optional), protecting the whole machine
# with its daily backup policy.
#
# This is machine-level, application-consistent backup. Workloads that
# need point-in-time restore of the databases themselves also want a
# log backup chain: the shared module's auto_backup input hands that to
# the SQL IaaS agent, which writes to a storage account it authenticates
# to with an access key. That account has to allow shared key
# authorisation, so it is wired up per deployment rather than switched
# on here by default.
# ------------------------------------------------------------

module "recovery_services_vault" {
  source = "../../shared/recovery-services-vault"

  count = var.enable_backup ? 1 : 0

  name                 = "rsv-${local.name_suffix}"
  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  daily_retention_days = var.backup_daily_retention_days
  tags                 = local.common_tags
}

# The vault only accepts traffic through its private endpoint: backup
# traffic resolves it through the geo-specific backup zone plus the
# blob and queue zones the backup service also uses.
data "azurerm_private_dns_zone" "backup" {
  provider = azurerm.hub

  count = var.enable_backup ? 1 : 0

  name                = var.backup_private_endpoint_dns_zone_name
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_private_dns_zone" "backup_blob" {
  provider = azurerm.hub

  count = var.enable_backup ? 1 : 0

  name                = "privatelink.blob.core.windows.net"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_private_dns_zone" "backup_queue" {
  provider = azurerm.hub

  count = var.enable_backup ? 1 : 0

  name                = "privatelink.queue.core.windows.net"
  resource_group_name = local.hub_dns_resource_group_name
}

module "recovery_vault_private_endpoint" {
  source = "../../shared/private-endpoint"

  count = var.enable_backup ? 1 : 0

  name                           = "pep-rsv-${local.name_suffix}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.recovery_services_vault[0].id
  subresource_names              = ["AzureBackup"]
  private_dns_zone_ids = [
    data.azurerm_private_dns_zone.backup[0].id,
    data.azurerm_private_dns_zone.backup_blob[0].id,
    data.azurerm_private_dns_zone.backup_queue[0].id,
  ]
  tags = local.common_tags
}

# ------------------------------------------------------------
# Application secrets, read with the machines' managed identities
#
# Connection strings and the like belong here rather than in
# configuration files on the machines. The vault is also where a
# customer-managed transparent data encryption key would live: hand
# the shared module a key_vault_credential pointing at it to have the
# SQL Server Connector wrap the database keys with it.
# ------------------------------------------------------------

module "key_vault" {
  source = "../../shared/key-vault"

  name                = local.key_vault_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags

  secrets_officer_principal_ids = var.key_vault_secrets_officer_principal_ids

  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.monitoring.id
}

module "key_vault_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-${local.key_vault_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.key_vault.id
  subresource_names              = ["vault"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.key_vault.id]
  tags                           = local.common_tags
}

resource "azurerm_role_assignment" "vm_key_vault_access" {
  count = var.virtual_machine_count

  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.sql_server_virtual_machine[count.index].principal_id
}

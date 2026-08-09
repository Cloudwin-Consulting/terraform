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

data "azurerm_subnet" "virtual_machines" {
  provider = azurerm.app_spoke

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

data "azurerm_private_dns_zone" "key_vault" {
  provider = azurerm.hub

  name                = "privatelink.vaultcore.azure.net"
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
# Windows Server virtual machines - example IaaS workload
#
# The virtual machines have no public IP addresses and only accept RDP
# from Azure Bastion in the hub, enforced by the spoke's network
# security group. The admin password is never committed to source
# control: it is read from a secret pre-loaded into the spoke's
# platform key vault when admin_password_key_vault_secret is set,
# otherwise each machine gets its own password generated at deployment
# time (retrieve with
# `terraform output -json virtual_machine_admin_passwords` or rotate
# with `az vm user update`). Scale out with virtual_machine_count and
# front the machines with the optional internal load balancer.
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

  # Recovery Services only accepts a private endpoint while the vault
  # has no registered backup items, so the machines (and their backup
  # registrations) wait for the endpoint.
  depends_on = [module.recovery_vault_private_endpoint]

  name                       = local.vm_names[count.index]
  computer_name              = var.virtual_machine_count == 1 ? var.computer_name : "${var.computer_name}${count.index}"
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  subnet_id                  = data.azurerm_subnet.virtual_machines.id
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
  data_disks = [
    for disk in var.data_disks : merge(disk, {
      name = "${local.vm_names[count.index]}-${disk.name}"
    })
  ]

  source_image_id = var.source_image_id

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
# Active Directory domain join (optional)
#
# Runs the repository's join-domain.ps1 on each machine through the Run
# Command service. The script fetches the join account's credentials
# from the spoke's platform key vault at runtime with the machine's
# managed identity (granted Key Vault Secrets User below), so the
# secret values never pass through Terraform or its state - the
# deployment only handles the vault and secret names.
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
# Recovery Services vault (optional), protecting the virtual machines
# with its daily backup policy
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
# Internal load balancer (optional) across the virtual machines
# ------------------------------------------------------------

module "load_balancer" {
  source = "../../shared/load-balancer"

  count = var.enable_load_balancer ? 1 : 0

  name                = "lbi-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = data.azurerm_subnet.virtual_machines.id
  rules               = var.load_balancer_rules
  zones               = length(var.availability_zones) > 0 ? var.availability_zones : null
  tags                = local.common_tags
}

resource "azurerm_network_interface_backend_address_pool_association" "this" {
  count = var.enable_load_balancer ? var.virtual_machine_count : 0

  network_interface_id    = module.virtual_machine[count.index].network_interface_id
  ip_configuration_name   = "internal"
  backend_address_pool_id = module.load_balancer[0].backend_address_pool_id
}

# ------------------------------------------------------------
# Application secrets, read with the virtual machine's managed identity
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
  principal_id         = module.virtual_machine[count.index].principal_id
}

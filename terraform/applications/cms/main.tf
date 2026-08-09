locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  # The upstream stacks this one looks up derive their names the
  # same way, from their own workload name and this environment.
  app_spoke_network_resource_group_name  = "rg-${var.app_spoke_deployment_name}-${var.environment}-network"
  app_spoke_virtual_network_name         = "vnet-${var.app_spoke_deployment_name}-${var.environment}"
  hub_dns_resource_group_name            = "rg-${var.hub_deployment_name}-${var.environment}-dns"
  log_analytics_workspace_name           = "log-${var.monitoring_deployment_name}-${var.environment}"
  monitoring_resource_group_name         = "rg-${var.monitoring_deployment_name}-${var.environment}"
  platform_key_vault_name                = "kv-${var.app_spoke_deployment_name}-${var.environment}"
  platform_key_vault_resource_group_name = "rg-${var.app_spoke_deployment_name}-${var.environment}-secrets"

  resource_group_name  = "rg-${local.name_suffix}"
  app_name             = coalesce(var.web_app_name, "app-${local.name_suffix}")
  mysql_server_name    = coalesce(var.mysql_server_name, "mysql-${local.name_suffix}")
  storage_account_name = coalesce(var.media_storage_account_name, "st${replace(local.name_suffix, "-", "")}")

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
# Existing platform resources: the application spoke network, its
# platform key vault, the hub's private DNS zones and the monitoring
# workspace.
# ------------------------------------------------------------

data "azurerm_subnet" "integration" {
  provider = azurerm.app_spoke

  name                 = var.integration_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

data "azurerm_subnet" "mysql" {
  provider = azurerm.app_spoke

  name                 = var.mysql_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

data "azurerm_subnet" "private_endpoints" {
  provider = azurerm.app_spoke

  name                 = var.private_endpoint_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

data "azurerm_private_dns_zone" "app_service" {
  provider = azurerm.hub

  name                = "privatelink.azurewebsites.net"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_private_dns_zone" "mysql" {
  provider = azurerm.hub

  name                = "privatelink.mysql.database.azure.com"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_private_dns_zone" "blob" {
  provider = azurerm.hub

  name                = "privatelink.blob.core.windows.net"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_log_analytics_workspace" "monitoring" {
  provider = azurerm.monitoring

  name                = local.log_analytics_workspace_name
  resource_group_name = local.monitoring_resource_group_name
}

# This stack demonstrates consuming the spoke's platform key vault
# directly instead of deploying its own: the database password is
# pre-loaded there and both the deployment and the running app read
# the same secret. Note the value still passes through the Terraform
# plan and state, so the pipeline publishes no decodable plan
# artifacts and the state backend must be treated as secret-bearing.
data "azurerm_key_vault" "platform" {
  provider = azurerm.key_vault

  name                = coalesce(var.database_password_key_vault_secret.key_vault_name, local.platform_key_vault_name)
  resource_group_name = coalesce(var.database_password_key_vault_secret.key_vault_resource_group_name, local.platform_key_vault_resource_group_name)
}

# Reading the secret happens over the vault's private data plane, so
# the deployment agent must run inside the network (e.g. self-hosted).
data "azurerm_key_vault_secret" "database_password" {
  provider = azurerm.key_vault

  name         = var.database_password_key_vault_secret.secret_name
  key_vault_id = data.azurerm_key_vault.platform.id
}

# ------------------------------------------------------------
# MySQL Flexible Server - the CMS database
#
# Deployed into the spoke's delegated MySQL subnet, so the server is
# only reachable from inside the network and resolves through the
# hub's mysql private DNS zone. The administrator password comes from
# the platform key vault, pre-loaded before this stack deploys.
# ------------------------------------------------------------

module "mysql" {
  source = "../../shared/mysql-server"

  name                   = local.mysql_server_name
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  sku_name               = var.mysql_sku
  administrator_password = data.azurerm_key_vault_secret.database_password.value
  delegated_subnet_id    = data.azurerm_subnet.mysql.id
  private_dns_zone_id    = data.azurerm_private_dns_zone.mysql.id
  backup_retention_days  = var.mysql_backup_retention_days
  high_availability      = var.mysql_high_availability

  databases = [var.database_name]

  tags = local.common_tags
}

# ------------------------------------------------------------
# Media storage - uploaded assets served by the CMS, written with the
# app's managed identity over the blob private endpoint.
# ------------------------------------------------------------

module "media_storage" {
  source = "../../shared/storage-account"

  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  containers          = ["media"]
  tags                = local.common_tags
}

module "media_storage_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-blob-${local.storage_account_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.media_storage.id
  subresource_names              = ["blob"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.blob.id]
  tags                           = local.common_tags
}

# ------------------------------------------------------------
# The CMS itself - a PHP web app with virtual network integration, a
# private endpoint and diagnostics to the monitoring workspace. The
# database password app setting is a key vault reference into the
# platform vault, resolved at runtime with the app's managed identity.
# ------------------------------------------------------------

module "app_service" {
  source = "../../shared/app-service"

  plan_name           = "asp-${local.name_suffix}"
  web_app_name        = local.app_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku_name            = var.app_service_sku

  worker_count           = var.app_service_worker_count
  zone_balancing_enabled = var.app_service_zone_balancing_enabled

  virtual_network_subnet_id  = data.azurerm_subnet.integration.id
  health_check_path          = "/healthz"
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.monitoring.id
  tags                       = local.common_tags

  application_stack = {
    php_version = "8.3"
  }

  app_settings = {
    DATABASE_HOST         = module.mysql.fqdn
    DATABASE_NAME         = var.database_name
    DATABASE_USER         = "mysqladmin"
    MEDIA_STORAGE_ACCOUNT = module.media_storage.name
    MEDIA_BLOB_ENDPOINT   = module.media_storage.primary_blob_endpoint

    # The same platform vault secret the deployment bootstrapped the
    # server with, resolved at runtime with the app's managed identity.
    DATABASE_PASSWORD = "@Microsoft.KeyVault(SecretUri=${data.azurerm_key_vault.platform.vault_uri}secrets/${var.database_password_key_vault_secret.secret_name}/)"
  }
}

# The app reads the database password from the platform vault and
# writes media with its identity.
resource "azurerm_role_assignment" "platform_vault_secrets_user" {
  scope                = data.azurerm_key_vault.platform.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.app_service.principal_id
}

resource "azurerm_role_assignment" "media_blob_contributor" {
  scope                = module.media_storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.app_service.principal_id
}

module "app_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-${local.app_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.app_service.web_app_id
  subresource_names              = ["sites"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.app_service.id]
  tags                           = local.common_tags
}

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

  resource_group_name    = "rg-${local.name_suffix}"
  app_name               = coalesce(var.web_app_name, "app-${local.name_suffix}")
  postgresql_server_name = coalesce(var.postgresql_server_name, "psql-${local.name_suffix}")
  redis_name             = coalesce(var.redis_name, "redis-${local.name_suffix}")
  app_configuration_name = coalesce(var.app_configuration_name, "appcs-${local.name_suffix}")
  key_vault_name         = coalesce(var.key_vault_name, "kv-${local.name_suffix}")

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

data "azurerm_subnet" "integration" {
  provider = azurerm.app_spoke

  name                 = var.integration_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

data "azurerm_subnet" "postgresql" {
  provider = azurerm.app_spoke

  name                 = var.postgresql_subnet_name
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

data "azurerm_private_dns_zone" "postgresql" {
  provider = azurerm.hub

  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_private_dns_zone" "redis" {
  provider = azurerm.hub

  name                = "privatelink.redis.cache.windows.net"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_private_dns_zone" "app_configuration" {
  provider = azurerm.hub

  name                = "privatelink.azconfig.io"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_private_dns_zone" "key_vault" {
  provider = azurerm.hub

  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_log_analytics_workspace" "monitoring" {
  provider = azurerm.monitoring

  name                = local.log_analytics_workspace_name
  resource_group_name = local.monitoring_resource_group_name
}

# The database password is pre-loaded into the spoke's platform key
# vault: the deployment bootstraps the server from it and the running
# API resolves the same secret at runtime. Note the value still passes
# through the Terraform plan and state, so the pipeline publishes no
# decodable plan artifacts.
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
# PostgreSQL Flexible Server - the API's relational store
#
# Deployed into the spoke's delegated PostgreSQL subnet, so the server
# is only reachable from inside the network and resolves through the
# hub's postgres private DNS zone. The administrator password comes
# from the platform key vault; production databases should also
# bootstrap an Entra database principal for the API's managed identity
# through the optional Entra administrator.
# ------------------------------------------------------------

module "postgresql" {
  source = "../../shared/postgresql-server"

  name                   = local.postgresql_server_name
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  sku_name               = var.postgresql_sku
  storage_mb             = var.postgresql_storage_mb
  administrator_password = data.azurerm_key_vault_secret.database_password.value
  delegated_subnet_id    = data.azurerm_subnet.postgresql.id
  private_dns_zone_id    = data.azurerm_private_dns_zone.postgresql.id
  backup_retention_days  = var.postgresql_backup_retention_days
  high_availability      = var.postgresql_high_availability

  entra_authentication_enabled = true
  entra_administrator          = var.postgresql_entra_administrator

  databases = [var.database_name]

  tags = local.common_tags
}

# ------------------------------------------------------------
# Redis cache - session and response caching. Microsoft Entra ID is the
# only authentication path (access keys are disabled by the module).
# ------------------------------------------------------------

module "redis" {
  source = "../../shared/redis-cache"

  name                = local.redis_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku_name            = var.redis_sku
  family              = var.redis_family
  capacity            = var.redis_capacity
  zones               = var.redis_zones
  tags                = local.common_tags
}

module "redis_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-${local.redis_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.redis.id
  subresource_names              = ["redisCache"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.redis.id]
  tags                           = local.common_tags
}

# ------------------------------------------------------------
# App Configuration - centralised settings and feature flags, read by
# the API with its managed identity.
# ------------------------------------------------------------

module "app_configuration" {
  source = "../../shared/app-configuration"

  name                = local.app_configuration_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = var.app_configuration_sku
  tags                = local.common_tags
}

module "app_configuration_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-${local.app_configuration_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.app_configuration.id
  subresource_names              = ["configurationStores"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.app_configuration.id]
  tags                           = local.common_tags
}

# ------------------------------------------------------------
# The API itself - App Service with virtual network integration, a
# private endpoint and diagnostics to the monitoring workspace.
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
    dotnet_version = "8.0"
  }

  app_settings = {
    APP_CONFIGURATION_ENDPOINT = module.app_configuration.endpoint
    REDIS_HOSTNAME             = module.redis.hostname
    REDIS_SSL_PORT             = tostring(module.redis.ssl_port)
    POSTGRESQL_FQDN            = module.postgresql.fqdn
    POSTGRESQL_DATABASE        = var.database_name
    POSTGRESQL_USER            = "psqladmin"
    KEY_VAULT_URI              = module.key_vault.vault_uri

    # The same platform vault secret the deployment bootstrapped the
    # server with, resolved at runtime with the API's managed identity.
    # Move the API to an Entra database principal once one has been
    # bootstrapped on the server.
    POSTGRESQL_PASSWORD = "@Microsoft.KeyVault(SecretUri=${data.azurerm_key_vault.platform.vault_uri}secrets/${var.database_password_key_vault_secret.secret_name}/)"

    # A key vault reference: resolved at runtime with the app's managed
    # identity, so rotating the secret in the vault needs no
    # redeployment. Pre-load the app-secret secret through the Secrets
    # Officer flow.
    APP_SECRET = "@Microsoft.KeyVault(SecretUri=${module.key_vault.vault_uri}secrets/app-secret/)"
  }
}

# The API reads configuration and feature flags with its identity.
resource "azurerm_role_assignment" "app_configuration_reader" {
  scope                = module.app_configuration.id
  role_definition_name = "App Configuration Data Reader"
  principal_id         = module.app_service.principal_id
}

# Access keys are disabled on the cache, so the API's identity is
# assigned the built-in Data Contributor access policy to authenticate
# with Microsoft Entra ID.
resource "azurerm_redis_cache_access_policy_assignment" "api" {
  name               = "api"
  redis_cache_id     = module.redis.id
  access_policy_name = "Data Contributor"
  object_id          = module.app_service.principal_id
  object_id_alias    = local.app_name
}

# The API resolves the database password reference from the platform
# vault at runtime.
resource "azurerm_role_assignment" "platform_vault_secrets_user" {
  scope                = data.azurerm_key_vault.platform.id
  role_definition_name = "Key Vault Secrets User"
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

# ------------------------------------------------------------
# Application secrets, read with the API's managed identity
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

resource "azurerm_role_assignment" "key_vault_secrets_user" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.app_service.principal_id
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

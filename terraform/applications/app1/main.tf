locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  # The upstream stacks this one looks up derive their names the
  # same way, from their own workload name and this environment.
  app_spoke_network_resource_group_name = "rg-${var.app_spoke_deployment_name}-${var.environment}-network"
  app_spoke_resource_group_name         = "rg-${var.app_spoke_deployment_name}-${var.environment}"
  app_spoke_virtual_network_name        = "vnet-${var.app_spoke_deployment_name}-${var.environment}"
  front_door_profile_name               = coalesce(var.front_door_profile_name, "afd-${var.app_spoke_deployment_name}-${var.environment}")
  hub_dns_resource_group_name           = "rg-${var.hub_deployment_name}-${var.environment}-dns"
  log_analytics_workspace_name          = "log-${var.monitoring_deployment_name}-${var.environment}"
  monitoring_resource_group_name        = "rg-${var.monitoring_deployment_name}-${var.environment}"

  resource_group_name  = "rg-${local.name_suffix}"
  web_app_name         = coalesce(var.web_app_name, "app-${local.name_suffix}")
  storage_account_name = coalesce(var.storage_account_name, "st${replace(local.name_suffix, "-", "")}")
  key_vault_name       = coalesce(var.key_vault_name, "kv-${local.name_suffix}")

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

data "azurerm_subnet" "app_integration" {
  provider = azurerm.app_spoke

  name                 = var.app_integration_subnet_name
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

data "azurerm_private_dns_zone" "blob" {
  provider = azurerm.hub

  name                = "privatelink.blob.core.windows.net"
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

# ------------------------------------------------------------
# App1 - example Node.js web app
#
# Inbound traffic arrives through a private endpoint in the spoke's
# private endpoint subnet. Outbound traffic leaves through regional
# virtual network integration.
# ------------------------------------------------------------

module "app_service" {
  source = "../../shared/app-service"

  plan_name                 = "asp-${local.name_suffix}"
  web_app_name              = local.web_app_name
  resource_group_name       = azurerm_resource_group.this.name
  location                  = azurerm_resource_group.this.location
  sku_name                  = var.app_service_sku
  worker_count              = var.app_service_worker_count
  zone_balancing_enabled    = var.app_service_zone_balancing_enabled
  virtual_network_subnet_id = data.azurerm_subnet.app_integration.id
  health_check_path         = "/healthz"
  tags                      = local.common_tags

  application_stack = {
    node_version = "20-lts"
  }

  app_settings = {
    STORAGE_ACCOUNT_BLOB_ENDPOINT = module.storage.primary_blob_endpoint
    STORAGE_CONTAINER_NAME        = "app-data"
    KEY_VAULT_URI                 = module.key_vault.vault_uri

    # A key vault reference: App Service resolves the secret at runtime
    # with the app's managed identity, so rotating the secret in the
    # vault needs no redeployment. Pre-load the app-secret secret
    # through the Secrets Officer flow.
    APP_SECRET = "@Microsoft.KeyVault(SecretUri=${module.key_vault.vault_uri}secrets/app-secret/)"
  }

  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.monitoring.id
}

module "app_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-${local.web_app_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.app_service.web_app_id
  subresource_names              = ["sites"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.app_service.id]
  tags                           = local.common_tags
}

# ------------------------------------------------------------
# Application storage, accessed with the web app's managed identity
# ------------------------------------------------------------

module "storage" {
  source = "../../shared/storage-account"

  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  containers          = ["app-data"]
  tags                = local.common_tags

  backup = var.enable_storage_backup ? {
    backup_vault_id           = module.backup_vault[0].id
    backup_vault_principal_id = module.backup_vault[0].principal_id
    backup_policy_id          = module.backup_vault[0].blob_backup_policy_id
  } : null
}

# ------------------------------------------------------------
# Blob backup (optional) through a Data Protection backup vault
# ------------------------------------------------------------

module "backup_vault" {
  source = "../../shared/backup-vault"

  count = var.enable_storage_backup ? 1 : 0

  name                = "bvault-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags
}

module "storage_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-blob-${local.storage_account_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.storage.id
  subresource_names              = ["blob"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.blob.id]
  tags                           = local.common_tags
}

resource "azurerm_role_assignment" "app_storage_access" {
  scope                = module.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.app_service.principal_id
}

# ------------------------------------------------------------
# Application secrets, read with the web app's managed identity
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

resource "azurerm_role_assignment" "app_key_vault_access" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.app_service.principal_id
}

# ------------------------------------------------------------
# Front Door endpoint (optional) on the spoke's shared profile
#
# The origin is reached over Private Link, so the web app stays
# unreachable from the public internet. Approve the pending private
# endpoint connection on the web app after the first deployment.
# ------------------------------------------------------------

data "azurerm_cdn_frontdoor_profile" "spoke" {
  provider = azurerm.app_spoke

  count = var.enable_front_door_endpoint ? 1 : 0

  name                = local.front_door_profile_name
  resource_group_name = local.app_spoke_resource_group_name

  lifecycle {
    # The endpoint reaches the private app through a Private Link
    # origin, which only Front Door Premium supports.
    postcondition {
      condition     = self.sku_name == "Premium_AzureFrontDoor"
      error_message = "The spoke's Front Door profile must be Premium_AzureFrontDoor: private link origins are not supported on the Standard SKU."
    }
  }
}

module "front_door_endpoint" {
  source = "../../shared/front-door-endpoint"

  count = var.enable_front_door_endpoint ? 1 : 0

  # The endpoint and its origin group, origin and route live on the
  # spoke's Front Door profile, so they are created in the spoke's
  # subscription.
  providers = {
    azurerm = azurerm.app_spoke
  }

  name                  = coalesce(var.front_door_endpoint_name, "fde-${local.name_suffix}")
  front_door_profile_id = data.azurerm_cdn_frontdoor_profile.spoke[0].id
  origin_host_name      = module.app_service.default_hostname
  health_probe_path     = "/healthz"
  tags                  = local.common_tags

  private_link = {
    target_id   = module.app_service.web_app_id
    target_type = "sites"
    location    = azurerm_resource_group.this.location
  }
}

# ------------------------------------------------------------
# Traffic Manager (optional) - DNS-based routing to the app
#
# Traffic Manager probes over the public internet and the app is
# private, so the endpoint is served without probing. Add endpoints in
# other regions to route across multiple deployments.
# ------------------------------------------------------------

module "traffic_manager" {
  source = "../../shared/traffic-manager"

  count = var.enable_traffic_manager ? 1 : 0

  name                = "traf-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  dns_relative_name   = coalesce(var.traffic_manager_dns_name, local.name_suffix)
  tags                = local.common_tags

  external_endpoints = [
    {
      name                 = "primary"
      target               = module.app_service.default_hostname
      priority             = 1
      always_serve_enabled = true
    }
  ]
}

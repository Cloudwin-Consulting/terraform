locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  # The upstream stacks this one looks up derive their names the
  # same way, from their own workload name and this environment.
  app_spoke_network_resource_group_name = "rg-${var.app_spoke_deployment_name}-${var.environment}-network"
  app_spoke_virtual_network_name        = "vnet-${var.app_spoke_deployment_name}-${var.environment}"
  hub_dns_resource_group_name           = "rg-${var.hub_deployment_name}-${var.environment}-dns"
  log_analytics_workspace_name          = "log-${var.monitoring_deployment_name}-${var.environment}"
  monitoring_resource_group_name        = "rg-${var.monitoring_deployment_name}-${var.environment}"

  resource_group_name  = "rg-${local.name_suffix}"
  logic_app_name       = coalesce(var.logic_app_name, "logic-${local.name_suffix}")
  storage_account_name = coalesce(var.storage_account_name, "st${replace(local.name_suffix, "-", "")}")
  key_vault_name       = coalesce(var.key_vault_name, "kv-${local.name_suffix}")

  # The Logic Apps runtime reaches its storage account over blob, file,
  # queue and table, so each service gets a private endpoint.
  storage_private_endpoints = {
    blob  = data.azurerm_private_dns_zone.blob.id
    file  = data.azurerm_private_dns_zone.file.id
    queue = data.azurerm_private_dns_zone.queue.id
    table = data.azurerm_private_dns_zone.table.id
  }

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

data "azurerm_private_dns_zone" "file" {
  provider = azurerm.hub

  name                = "privatelink.file.core.windows.net"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_private_dns_zone" "queue" {
  provider = azurerm.hub

  name                = "privatelink.queue.core.windows.net"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_private_dns_zone" "table" {
  provider = azurerm.hub

  name                = "privatelink.table.core.windows.net"
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
# Logic app - example integration workload
#
# A Logic App Standard reached through a private endpoint, with
# regional virtual network integration so the runtime can reach its
# storage account over the private endpoints.
# ------------------------------------------------------------

module "logic_app" {
  source = "../../shared/logic-app"

  plan_name                  = "asp-${local.name_suffix}"
  logic_app_name             = local.logic_app_name
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  sku_name                   = var.logic_app_sku
  storage_account_name       = module.storage.name
  storage_account_access_key = module.storage.primary_access_key
  virtual_network_subnet_id  = data.azurerm_subnet.app_integration.id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.monitoring.id
  tags                       = local.common_tags

  app_settings = {
    # The runtime creates its content share on the private-only storage
    # account over the virtual network.
    WEBSITE_CONTENTOVERVNET = "1"
    KEY_VAULT_URI           = module.key_vault.vault_uri

    # A key vault reference: resolved at runtime with the app's managed
    # identity, so rotating the secret in the vault needs no
    # redeployment. Pre-load the app-secret secret through the Secrets
    # Officer flow.
    APP_SECRET = "@Microsoft.KeyVault(SecretUri=${module.key_vault.vault_uri}secrets/app-secret/)"
  }
}

module "logic_app_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-${local.logic_app_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.logic_app.logic_app_id
  subresource_names              = ["sites"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.app_service.id]
  tags                           = local.common_tags
}

# ------------------------------------------------------------
# Runtime storage
#
# The Logic Apps runtime requires shared key access to its storage
# account, so this account is dedicated to the runtime and holds no
# application data. Its data plane stays private behind the endpoints.
# ------------------------------------------------------------

module "storage" {
  source = "../../shared/storage-account"

  name                      = local.storage_account_name
  resource_group_name       = azurerm_resource_group.this.name
  location                  = azurerm_resource_group.this.location
  shared_access_key_enabled = true
  tags                      = local.common_tags
}

module "storage_private_endpoints" {
  source = "../../shared/private-endpoint"

  for_each = local.storage_private_endpoints

  name                           = "pep-${each.key}-${local.storage_account_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.storage.id
  subresource_names              = [each.key]
  private_dns_zone_ids           = [each.value]
  tags                           = local.common_tags
}

# ------------------------------------------------------------
# Application secrets, read with the logic app's managed identity
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

resource "azurerm_role_assignment" "logic_app_key_vault_access" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.logic_app.principal_id
}

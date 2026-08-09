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
  event_hub_name       = coalesce(var.event_hub_namespace_name, "evhns-${local.name_suffix}")
  cosmos_account_name  = coalesce(var.cosmos_account_name, "cosno-${local.name_suffix}")
  function_app_name    = coalesce(var.function_app_name, "func-${local.name_suffix}")
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

data "azurerm_subnet" "integration" {
  provider = azurerm.app_spoke

  name                 = var.integration_subnet_name
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

data "azurerm_private_dns_zone" "service_bus" {
  provider = azurerm.hub

  name                = "privatelink.servicebus.windows.net"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_private_dns_zone" "cosmos" {
  provider = azurerm.hub

  name                = "privatelink.documents.azure.com"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_private_dns_zone" "blob" {
  provider = azurerm.hub

  name                = "privatelink.blob.core.windows.net"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_private_dns_zone" "queue" {
  provider = azurerm.hub

  name                = "privatelink.queue.core.windows.net"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_private_dns_zone" "file" {
  provider = azurerm.hub

  name                = "privatelink.file.core.windows.net"
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
# Event Hubs - the telemetry ingestion front door. Producers send with
# their managed identities over the namespace's private endpoint
# (Event Hubs shares the servicebus privatelink zone).
# ------------------------------------------------------------

module "event_hub" {
  source = "../../shared/event-hub"

  name                     = local.event_hub_name
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  sku                      = var.event_hub_sku
  capacity                 = var.event_hub_capacity
  auto_inflate_enabled     = var.event_hub_auto_inflate_enabled
  maximum_throughput_units = var.event_hub_maximum_throughput_units
  tags                     = local.common_tags

  event_hubs = {
    telemetry = {
      partition_count   = var.event_hub_partition_count
      message_retention = var.event_hub_message_retention
    }
  }
}

module "event_hub_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-${local.event_hub_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.event_hub.id
  subresource_names              = ["namespace"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.service_bus.id]
  tags                           = local.common_tags
}

# ------------------------------------------------------------
# Cosmos DB - the materialised view the consumer writes into. Local
# (key) authentication is disabled by the module, so all access is
# with Microsoft Entra ID.
# ------------------------------------------------------------

module "cosmos" {
  source = "../../shared/cosmos-db"

  name                = local.cosmos_account_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  consistency_level   = "Session"
  zone_redundant      = var.cosmos_zone_redundant

  automatic_failover_enabled = var.cosmos_automatic_failover_enabled
  additional_geo_locations   = var.cosmos_additional_geo_locations

  sql_databases = [var.cosmos_database_name]

  tags = local.common_tags
}

# The container the consumer writes the materialised view into,
# partitioned by device so lookups and writes stay single-partition.
resource "azurerm_cosmosdb_sql_container" "events" {
  name                = var.cosmos_container_name
  resource_group_name = azurerm_resource_group.this.name
  account_name        = module.cosmos.name
  database_name       = var.cosmos_database_name
  partition_key_paths = ["/deviceId"]

  depends_on = [module.cosmos]
}

module "cosmos_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-${local.cosmos_account_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.cosmos.id
  subresource_names              = ["Sql"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.cosmos.id]
  tags                           = local.common_tags
}

# ------------------------------------------------------------
# Consumer function - reads the telemetry event hub and writes the
# materialised view to Cosmos DB, all with its managed identity.
# ------------------------------------------------------------

module "storage" {
  source = "../../shared/storage-account"

  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags

  # The Elastic Premium content share mounts with shared-key
  # authorisation only, so keys stay enabled on this dedicated host
  # account; data plane access still flows through the private
  # endpoints.
  shared_access_key_enabled = true
}

# The Functions host reaches all four storage services - blob and
# queue for the runtime, file for the Elastic Premium content share and
# table for host metadata - so each gets a private endpoint.
module "storage_private_endpoints" {
  source = "../../shared/private-endpoint"

  for_each = {
    blob  = data.azurerm_private_dns_zone.blob.id
    queue = data.azurerm_private_dns_zone.queue.id
    file  = data.azurerm_private_dns_zone.file.id
    table = data.azurerm_private_dns_zone.table.id
  }

  name                           = "pep-${each.key}-${local.storage_account_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.storage.id
  subresource_names              = [each.key]
  private_dns_zone_ids           = [each.value]
  tags                           = local.common_tags
}

module "function_app" {
  source = "../../shared/function-app"

  plan_name           = "asp-${local.name_suffix}"
  function_app_name   = local.function_app_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku_name            = var.function_app_sku

  worker_count           = var.function_app_worker_count
  zone_balancing_enabled = var.function_app_zone_balancing_enabled

  storage_account_name       = module.storage.name
  storage_account_id         = module.storage.id
  storage_account_access_key = module.storage.primary_access_key

  # The storage account deploys in this same apply, so its ID is unknown
  # at plan time; the plan-time flag decides the role assignments exist.
  enable_storage_role_assignments = true

  virtual_network_subnet_id  = data.azurerm_subnet.integration.id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.monitoring.id
  tags                       = local.common_tags

  application_stack = {
    dotnet_version = "8.0"
  }

  app_settings = {
    # The Elastic Premium content share lives on the private-only
    # storage account, so the runtime must reach it through the
    # integration subnet.
    WEBSITE_CONTENTOVERVNET = "1"

    # Identity-based trigger connection: the host connects to the
    # namespace with its managed identity, no connection string.
    EventHubConnection__fullyQualifiedNamespace = "${local.event_hub_name}.servicebus.windows.net"
    EVENT_HUB_NAME                              = "telemetry"

    COSMOS_ENDPOINT  = module.cosmos.endpoint
    COSMOS_DATABASE  = var.cosmos_database_name
    COSMOS_CONTAINER = azurerm_cosmosdb_sql_container.events.name
    KEY_VAULT_URI    = module.key_vault.vault_uri
  }
}

# The consumer's identity receives events from the namespace and
# writes documents through Cosmos DB's data plane role.
resource "azurerm_role_assignment" "event_hub_receiver" {
  scope                = module.event_hub.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = module.function_app.principal_id
}

resource "azurerm_cosmosdb_sql_role_assignment" "function_data_contributor" {
  resource_group_name = azurerm_resource_group.this.name
  account_name        = module.cosmos.name
  scope               = module.cosmos.id

  # 00000000-0000-0000-0000-000000000002 is the built-in Cosmos DB Data
  # Contributor data plane role.
  role_definition_id = "${module.cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id       = module.function_app.principal_id
}

module "function_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-${local.function_app_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.function_app.function_app_id
  subresource_names              = ["sites"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.app_service.id]
  tags                           = local.common_tags
}

# ------------------------------------------------------------
# Application secrets, read with the function's managed identity
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
  principal_id         = module.function_app.principal_id
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

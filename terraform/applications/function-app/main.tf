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
  function_app_name    = coalesce(var.function_app_name, "func-${local.name_suffix}")
  storage_account_name = coalesce(var.storage_account_name, "st${replace(local.name_suffix, "-", "")}")
  service_bus_name     = coalesce(var.service_bus_name, "sb-${local.name_suffix}")
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

data "azurerm_private_dns_zone" "service_bus" {
  provider = azurerm.hub

  name                = "privatelink.servicebus.windows.net"
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
# Function app - example event-driven workload
#
# The function app processes messages from a Service Bus queue with
# its managed identity. Inbound traffic arrives through a private
# endpoint; outbound traffic leaves through regional virtual network
# integration, which the private Service Bus and storage endpoints
# require.
# ------------------------------------------------------------

module "function_app" {
  source = "../../shared/function-app"

  plan_name                 = "asp-${local.name_suffix}"
  function_app_name         = local.function_app_name
  resource_group_name       = azurerm_resource_group.this.name
  location                  = azurerm_resource_group.this.location
  sku_name                  = var.function_app_sku
  worker_count              = var.function_app_worker_count
  zone_balancing_enabled    = var.function_app_zone_balancing_enabled
  storage_account_name      = module.storage.name
  storage_account_id        = module.storage.id
  virtual_network_subnet_id = data.azurerm_subnet.app_integration.id
  tags                      = local.common_tags

  # The storage account deploys in this same apply, so its ID is unknown
  # at plan time; the plan-time flag decides the role assignments exist.
  enable_storage_role_assignments = true

  application_stack = {
    dotnet_version = "8.0"
  }

  # This example runs on dedicated (B1/P1v3) plans, which deploy from
  # the package and need no Azure Files content share. On an Elastic
  # Premium SKU, also pass storage_account_access_key (see the
  # event-pipeline stack) so the platform can mount the content share.
  app_settings = {
    ServiceBusConnection__fullyQualifiedNamespace = "${local.service_bus_name}.servicebus.windows.net"
    QUEUE_NAME                                    = "jobs"
    KEY_VAULT_URI                                 = module.key_vault.vault_uri

    # A key vault reference: resolved at runtime with the app's managed
    # identity, so rotating the secret in the vault needs no
    # redeployment. Pre-load the app-secret secret through the Secrets
    # Officer flow.
    APP_SECRET = "@Microsoft.KeyVault(SecretUri=${module.key_vault.vault_uri}secrets/app-secret/)"
  }

  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.monitoring.id
}

module "function_app_private_endpoint" {
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
# Runtime storage, accessed with the function app's managed identity
# ------------------------------------------------------------

module "storage" {
  source = "../../shared/storage-account"

  name                = local.storage_account_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags
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

# ------------------------------------------------------------
# Service Bus queue, consumed with the function app's managed identity
# ------------------------------------------------------------

module "service_bus" {
  source = "../../shared/service-bus"

  name                = local.service_bus_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  capacity            = var.service_bus_capacity
  queues              = ["jobs"]
  tags                = local.common_tags
}

module "service_bus_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-${local.service_bus_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.service_bus.id
  subresource_names              = ["namespace"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.service_bus.id]
  tags                           = local.common_tags
}

# The function app's identity receives from and sends to the
# namespace's queues.
module "service_bus_receive_role" {
  source = "../../shared/rbac-role-assignment"

  scope                = module.service_bus.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_type       = "ServicePrincipal"

  principals = {
    function-app = module.function_app.principal_id
  }
}

module "service_bus_send_role" {
  source = "../../shared/rbac-role-assignment"

  scope                = module.service_bus.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_type       = "ServicePrincipal"

  principals = {
    function-app = module.function_app.principal_id
  }
}

# ------------------------------------------------------------
# Application secrets, read with the function app's managed identity
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

module "key_vault_secrets_user_role" {
  source = "../../shared/rbac-role-assignment"

  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_type       = "ServicePrincipal"

  principals = {
    function-app = module.function_app.principal_id
  }
}

# ------------------------------------------------------------
# Just-in-time operations access
#
# Operators hold no standing access to the workload's resource group.
# Instead the principals in pim_operations_principals (e.g. an
# operations group) are made eligible for the operations role through
# Privileged Identity Management and activate it when needed - with
# multi-factor authentication and a justification, for at most the
# configured duration. Requires Microsoft Entra ID P2 licensing.
# ------------------------------------------------------------

module "operations_pim" {
  source = "../../shared/pim"
  count  = length(var.pim_operations_principals) > 0 ? 1 : 0

  scope                = azurerm_resource_group.this.id
  role_definition_name = var.pim_operations_role_definition_name
  eligible_principals  = var.pim_operations_principals

  role_management_policy = {
    activation = {
      maximum_duration                   = var.pim_operations_maximum_activation_duration
      require_multifactor_authentication = true
      require_justification              = true
    }
  }
}

# ------------------------------------------------------------
# State moves: these role assignments were standalone resources
# before the rbac-role-assignment module, so the moves keep existing
# deployments' assignments in place instead of recreating them.
# ------------------------------------------------------------

moved {
  from = azurerm_role_assignment.function_service_bus_receive
  to   = module.service_bus_receive_role.azurerm_role_assignment.this["function-app"]
}

moved {
  from = azurerm_role_assignment.function_service_bus_send
  to   = module.service_bus_send_role.azurerm_role_assignment.this["function-app"]
}

moved {
  from = azurerm_role_assignment.function_key_vault_access
  to   = module.key_vault_secrets_user_role.azurerm_role_assignment.this["function-app"]
}

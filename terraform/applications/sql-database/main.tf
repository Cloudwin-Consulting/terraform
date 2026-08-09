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

  resource_group_name = "rg-${local.name_suffix}"
  sql_server_name     = coalesce(var.sql_server_name, "sql-${local.name_suffix}")

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
# Existing platform resources: the application spoke network and the
# hub's private DNS zones.
# ------------------------------------------------------------

data "azurerm_subnet" "private_endpoints" {
  provider = azurerm.app_spoke

  name                 = var.private_endpoint_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

data "azurerm_log_analytics_workspace" "monitoring" {
  provider = azurerm.monitoring

  name                = local.log_analytics_workspace_name
  resource_group_name = local.monitoring_resource_group_name
}

data "azurerm_private_dns_zone" "sql" {
  provider = azurerm.hub

  name                = "privatelink.database.windows.net"
  resource_group_name = local.hub_dns_resource_group_name
}

# ------------------------------------------------------------
# SQL server and database - example data platform
#
# Authentication is Microsoft Entra ID only: applications connect with
# their managed identities and administrators with the Entra ID group
# set as server administrator, so no credentials exist to store or
# rotate. Grant applications access with CREATE USER ... FROM EXTERNAL
# PROVIDER from inside the network.
# ------------------------------------------------------------

module "sql_server" {
  source = "../../shared/sql-server"

  name                = local.sql_server_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags

  azuread_administrator = {
    login_username = var.sql_entra_admin_login_username
    object_id      = var.sql_entra_admin_object_id
  }

  databases = {
    (var.database_name) = {
      sku_name                    = var.database_sku
      max_size_gb                 = var.database_max_size_gb
      zone_redundant              = var.database_zone_redundant
      auto_pause_delay_in_minutes = var.database_auto_pause_delay_in_minutes
    }
  }

  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.monitoring.id
}

module "sql_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-${local.sql_server_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.sql_server.id
  subresource_names              = ["sqlServer"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.sql.id]
  tags                           = local.common_tags
}

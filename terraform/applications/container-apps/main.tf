locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  # The upstream stacks this one looks up derive their names the
  # same way, from their own workload name and this environment.
  app_spoke_network_resource_group_name = "rg-${var.app_spoke_deployment_name}-${var.environment}-network"
  app_spoke_virtual_network_name        = "vnet-${var.app_spoke_deployment_name}-${var.environment}"
  hub_dns_resource_group_name           = "rg-${var.hub_deployment_name}-${var.environment}-dns"
  hub_network_resource_group_name       = "rg-${var.hub_deployment_name}-${var.environment}-network"
  hub_virtual_network_name              = "vnet-${var.hub_deployment_name}-${var.environment}"
  log_analytics_workspace_name          = "log-${var.monitoring_deployment_name}-${var.environment}"
  monitoring_resource_group_name        = "rg-${var.monitoring_deployment_name}-${var.environment}"

  resource_group_name     = "rg-${local.name_suffix}"
  environment_name        = "cae-${local.name_suffix}"
  container_app_name      = "ca-${local.name_suffix}"
  container_registry_name = coalesce(var.container_registry_name, "cr${replace(local.name_suffix, "-", "")}")
  key_vault_name          = coalesce(var.key_vault_name, "kv-${local.name_suffix}")

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
# hub network, the hub's private DNS zones and the monitoring
# workspace.
# ------------------------------------------------------------

data "azurerm_subnet" "container_apps" {
  provider = azurerm.app_spoke

  name                 = var.container_apps_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

data "azurerm_subnet" "private_endpoints" {
  provider = azurerm.app_spoke

  name                 = var.private_endpoint_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

data "azurerm_virtual_network" "app_spoke" {
  provider = azurerm.app_spoke

  name                = local.app_spoke_virtual_network_name
  resource_group_name = local.app_spoke_network_resource_group_name
}

data "azurerm_virtual_network" "hub" {
  provider = azurerm.hub

  name                = local.hub_virtual_network_name
  resource_group_name = local.hub_network_resource_group_name
}

data "azurerm_private_dns_zone" "key_vault" {
  provider = azurerm.hub

  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_private_dns_zone" "container_registry" {
  provider = azurerm.hub

  name                = "privatelink.azurecr.io"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_log_analytics_workspace" "monitoring" {
  provider = azurerm.monitoring

  name                = local.log_analytics_workspace_name
  resource_group_name = local.monitoring_resource_group_name
}

# ------------------------------------------------------------
# Container app environment - example container workload platform
#
# The environment joins the spoke's delegated infrastructure subnet
# and its ingress load balancer only has a private IP address. The
# environment's default domain gets its own private DNS zone, linked
# to the spoke and the hub, so container app names resolve to the
# internal load balancer from anywhere in the network.
# ------------------------------------------------------------

module "container_app_environment" {
  source = "../../shared/container-app-environment"

  name                     = local.environment_name
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  infrastructure_subnet_id = data.azurerm_subnet.container_apps.id
  zone_redundancy_enabled  = var.zone_redundancy_enabled
  tags                     = local.common_tags

  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.monitoring.id
}

module "container_apps_dns_zone" {
  source = "../../shared/private-dns-zone"

  name                = module.container_app_environment.default_domain
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  a_records = {
    "*" = {
      records = [module.container_app_environment.static_ip_address]
    }
  }

  virtual_network_links = {
    (local.app_spoke_virtual_network_name) = {
      virtual_network_id = data.azurerm_virtual_network.app_spoke.id
    }
    (local.hub_virtual_network_name) = {
      virtual_network_id = data.azurerm_virtual_network.hub.id
    }
  }
}

# ------------------------------------------------------------
# Container registry, pulled from with a user-assigned identity
#
# Registry pulls need a user-assigned identity because the image is
# pulled before a system-assigned identity could be granted access.
# ------------------------------------------------------------

module "container_registry" {
  source = "../../shared/container-registry"

  name                    = local.container_registry_name
  resource_group_name     = azurerm_resource_group.this.name
  location                = azurerm_resource_group.this.location
  push_principal_ids      = var.container_registry_push_principal_ids
  zone_redundancy_enabled = var.container_registry_zone_redundancy_enabled
  tags                    = local.common_tags
}

module "container_registry_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-${local.container_registry_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.container_registry.id
  subresource_names              = ["registry"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.container_registry.id]
  tags                           = local.common_tags
}

module "registry_pull_identity" {
  source = "../../shared/user-assigned-identity"

  name                = "id-${local.name_suffix}-acr"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags
}

resource "azurerm_role_assignment" "registry_pull" {
  scope                = module.container_registry.id
  role_definition_name = "AcrPull"
  principal_id         = module.registry_pull_identity.principal_id
}

# ------------------------------------------------------------
# Container app
#
# Starts from the public quickstart image so the first deployment
# succeeds before any image has been pushed to the registry. Point the
# image at the registry once application images are published there.
# ------------------------------------------------------------

module "container_app" {
  source = "../../shared/container-app"

  name                         = local.container_app_name
  container_app_environment_id = module.container_app_environment.id
  resource_group_name          = azurerm_resource_group.this.name
  identity_ids                 = [module.registry_pull_identity.id]
  image                        = var.container_image
  target_port                  = var.container_target_port
  cpu                          = var.container_cpu
  memory                       = var.container_memory
  min_replicas                 = var.min_replicas
  max_replicas                 = var.max_replicas
  tags                         = local.common_tags

  registries = [
    {
      server   = module.container_registry.login_server
      identity = module.registry_pull_identity.id
    }
  ]

  environment_variables = {
    KEY_VAULT_URI = module.key_vault.vault_uri
  }

  depends_on = [azurerm_role_assignment.registry_pull]
}

# ------------------------------------------------------------
# Application secrets, read with the container app's managed identity
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
  principal_id         = module.container_app.principal_id
}

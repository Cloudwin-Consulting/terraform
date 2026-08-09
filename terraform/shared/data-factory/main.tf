terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# An Azure Data Factory. The factory's own endpoint is reached through
# a private endpoint, and its integration runtimes run inside a managed
# virtual network, so pipeline activities leave through managed private
# endpoints to the data stores they read and write rather than over the
# public internet. Linked services authenticate with the factory's
# managed identity.
#
# Managed private endpoints arrive at their target pending approval,
# exactly as a Front Door private link origin does: approve each one on
# the target resource after the first deployment, or the pipelines
# using it will fail to connect.

locals {
  identity_type = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"
}

resource "azurerm_data_factory" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  # Secure defaults: no public endpoint on the factory, and activities
  # run inside the managed virtual network so their egress is
  # controlled by managed private endpoints.
  public_network_enabled          = var.public_network_enabled
  managed_virtual_network_enabled = var.managed_virtual_network_enabled

  purview_id = var.purview_id

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  # Customer-managed key encryption of the factory's stored
  # definitions. Requires a user-assigned identity granted wrap and
  # unwrap on a purge-protected vault.
  customer_managed_key_id          = var.customer_managed_key == null ? null : var.customer_managed_key.key_vault_key_id
  customer_managed_key_identity_id = var.customer_managed_key == null ? null : var.customer_managed_key.identity_id

  # Authoring against a repository rather than the live service, so
  # pipeline definitions are reviewed and versioned like the rest of
  # the estate. Leave both null to author against the factory itself.
  dynamic "github_configuration" {
    for_each = var.github_configuration == null ? [] : [var.github_configuration]

    content {
      account_name       = github_configuration.value.account_name
      branch_name        = github_configuration.value.branch_name
      repository_name    = github_configuration.value.repository_name
      root_folder        = github_configuration.value.root_folder
      git_url            = github_configuration.value.git_url
      publishing_enabled = github_configuration.value.publishing_enabled
    }
  }

  dynamic "vsts_configuration" {
    for_each = var.vsts_configuration == null ? [] : [var.vsts_configuration]

    content {
      account_name       = vsts_configuration.value.account_name
      branch_name        = vsts_configuration.value.branch_name
      project_name       = vsts_configuration.value.project_name
      repository_name    = vsts_configuration.value.repository_name
      root_folder        = vsts_configuration.value.root_folder
      tenant_id          = vsts_configuration.value.tenant_id
      publishing_enabled = vsts_configuration.value.publishing_enabled
    }
  }

  dynamic "global_parameter" {
    for_each = var.global_parameters

    content {
      name  = global_parameter.key
      type  = global_parameter.value.type
      value = global_parameter.value.value
    }
  }
}

# The Azure integration runtimes activities run on. Each joins the
# factory's managed virtual network, so its outbound traffic uses the
# managed private endpoints below.
resource "azurerm_data_factory_integration_runtime_azure" "this" {
  for_each = var.azure_integration_runtimes

  name                    = each.key
  data_factory_id         = azurerm_data_factory.this.id
  location                = each.value.location == null ? var.location : each.value.location
  description             = each.value.description
  compute_type            = each.value.compute_type
  core_count              = each.value.core_count
  time_to_live_min        = each.value.time_to_live_min
  cleanup_enabled         = each.value.cleanup_enabled
  virtual_network_enabled = var.managed_virtual_network_enabled
}

# Managed private endpoints from the factory's managed virtual network
# to the data stores it reads and writes. Each arrives at its target
# pending approval.
resource "azurerm_data_factory_managed_private_endpoint" "this" {
  for_each = var.managed_private_endpoints

  name               = each.key
  data_factory_id    = azurerm_data_factory.this.id
  target_resource_id = each.value.target_resource_id
  subresource_name   = each.value.subresource_name
  fqdns              = each.value.fqdns
}

# Sends logs and metrics to Log Analytics when a workspace is
# configured. Callers that create the workspace in the same apply must
# set enable_diagnostics themselves, because the workspace ID is unknown
# until apply and cannot decide the count.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_data_factory.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

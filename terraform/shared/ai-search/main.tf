terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# An Azure AI Search service. Queries and indexing calls arrive with
# Microsoft Entra ID and RBAC through a private endpoint: the admin and
# query API keys are disabled, so callers hold a role (Search Index
# Data Reader to query, Search Index Data Contributor to index) rather
# than a key.
#
# The service's own outbound connections - indexers reading a data
# source, skillsets calling an AI Services account - are made with its
# managed identity, and reach private targets through shared private
# link resources, which the caller creates against the data stores it
# indexes.

resource "azurerm_search_service" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  tags                = var.tags

  # Basic and above run one replica per unit of query throughput and
  # availability, and one partition per unit of index storage. The free
  # SKU is fixed at one of each.
  replica_count   = var.sku == "free" ? null : var.replica_count
  partition_count = var.sku == "free" ? null : var.partition_count

  # highDensity hosting packs many small indexes onto the standard3
  # SKU; every other SKU is default.
  hosting_mode = var.hosting_mode

  # Secure defaults: Microsoft Entra ID only (no API keys) and no
  # public network access. Data plane access is via a private endpoint.
  local_authentication_enabled = var.local_authentication_enabled
  authentication_failure_mode  = var.local_authentication_enabled ? var.authentication_failure_mode : null

  # An open endpoint carries an allow list, which the variable requires:
  # Search has no default-deny action, so an empty rule set restricts
  # nothing rather than denying everything. The free SKU supports no IP
  # rules at all, so it is the one open endpoint with none - the
  # variable rejects a list there rather than sending one that would be
  # refused.
  public_network_access_enabled = var.public_network_access_enabled
  allowed_ips                   = var.public_network_access_enabled && var.sku != "free" ? var.allowed_ips : []
  network_rule_bypass_option    = var.network_rule_bypass_option

  # Refuses to serve indexes whose customer-managed key encryption is
  # not in place, rather than silently falling back to platform keys.
  customer_managed_key_enforcement_enabled = var.customer_managed_key_enforcement_enabled

  semantic_search_sku = var.sku == "free" ? null : var.semantic_search_sku

  # Indexers and skillsets connect out with this identity instead of
  # connection strings. The free SKU supports no managed identity, so
  # it gets none.
  dynamic "identity" {
    for_each = var.sku == "free" ? [] : [1]

    content {
      type = "SystemAssigned"
    }
  }
}

# Sends logs and metrics to Log Analytics when a workspace is
# configured. Callers that create the workspace in the same apply must
# set enable_diagnostics themselves, because the workspace ID is unknown
# until apply and cannot decide the count.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_search_service.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

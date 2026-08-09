terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The tenant the vault joins is taken from the deployment identity.
data "azurerm_client_config" "current" {}

# The vault. Data plane access is with Microsoft Entra ID and RBAC
# through a private endpoint.
resource "azurerm_key_vault" "this" {
  #checkov:skip=CKV2_AZURE_32: Callers attach a private endpoint through the shared private-endpoint module - Checkov cannot link an azurerm_private_endpoint to this vault across module boundaries, so the graph check can never pass here. Public network access is disabled with a default-deny ACL below.
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.sku_name
  tags                = var.tags

  # Secure defaults: RBAC authorisation instead of access policies, purge
  # protection with soft delete, and no public network access. Data plane
  # access is via private endpoints only, so secrets are managed by
  # workloads at runtime with their managed identities rather than from
  # deployment agents outside the network.
  rbac_authorization_enabled    = true
  purge_protection_enabled      = var.purge_protection_enabled
  soft_delete_retention_days    = var.soft_delete_retention_days
  public_network_access_enabled = var.public_network_access_enabled

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

# Workloads read secrets with the Key Vault Secrets User role assigned
# by their stack. Populating secrets happens from inside the network
# (e.g. through the hub jump box) by the administrator principals
# granted Secrets Officer here.
resource "azurerm_role_assignment" "secrets_officers" {
  for_each = toset(var.secrets_officer_principal_ids)

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}

# Sends audit logs and metrics to Log Analytics when a workspace is
# configured. Callers that create the workspace in the same apply must
# set enable_diagnostics themselves, because the workspace ID is unknown
# until apply and cannot decide the count.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

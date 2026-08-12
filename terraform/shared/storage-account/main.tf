terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The storage account. Data plane access is with Microsoft Entra ID
# and RBAC through private endpoints.
resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV2_AZURE_33: Callers attach a private endpoint through the shared private-endpoint module - Checkov cannot link an azurerm_private_endpoint to this account across module boundaries, so the graph check can never pass here. Public network access is disabled with a default-deny network rule below.
  #checkov:skip=CKV_AZURE_33: Queue Storage Analytics logging (queue_properties) is only configurable through the data plane, which this account denies by design - queue requests are logged through the queue service diagnostic setting below instead.
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = var.account_kind
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  access_tier              = var.access_tier
  tags                     = var.tags

  # Secure defaults: TLS 1.2, HTTPS only, no shared key auth (use
  # Microsoft Entra ID and RBAC), no public network access and no
  # anonymous blob access - containers are always private. Data plane
  # access is via private endpoints only.
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = var.shared_access_key_enabled
  public_network_access_enabled     = var.public_network_access_enabled
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true

  identity {
    type = "SystemAssigned"
  }

  # SAS tokens asking for a longer lifetime than this are rejected
  # (the default action, Log, would only record the violation). Only
  # relevant when shared key authorisation is enabled, since account
  # SAS tokens are signed with the account keys.
  sas_policy {
    expiration_period = var.sas_expiration_period
    expiration_action = "Block"
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  # Identity-based authentication for the account's SMB file shares,
  # e.g. Microsoft Entra Kerberos for FSLogix profile shares mounted
  # by Entra joined session hosts.
  dynamic "azure_files_authentication" {
    for_each = var.azure_files_authentication == null ? [] : [var.azure_files_authentication]

    content {
      directory_type                 = azure_files_authentication.value.directory_type
      default_share_level_permission = azure_files_authentication.value.default_share_level_permission

      dynamic "active_directory" {
        for_each = azure_files_authentication.value.active_directory == null ? [] : [azure_files_authentication.value.active_directory]

        content {
          domain_name         = active_directory.value.domain_name
          domain_guid         = active_directory.value.domain_guid
          domain_sid          = active_directory.value.domain_sid
          storage_sid         = active_directory.value.storage_sid
          forest_name         = active_directory.value.forest_name
          netbios_domain_name = active_directory.value.netbios_domain_name
        }
      }
    }
  }

  blob_properties {
    versioning_enabled = var.blob_versioning_enabled

    delete_retention_policy {
      days = var.blob_soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.container_soft_delete_retention_days
    }
  }
}

# Grants the account's identity access to wrap and unwrap the
# customer-managed key. Azure Storage is on Key Vault's trusted
# services list, so the vault's default-deny network rules admit it -
# but only through the vault's public endpoint. The trusted-services
# bypass does not apply to a vault whose public endpoint is disabled,
# so the vault must be deployed with public network access enabled
# (the key-vault module's default-deny ACLs still reject everything
# except trusted services).
resource "azurerm_role_assignment" "customer_managed_key" {
  count = var.customer_managed_key == null ? 0 : 1

  scope                = var.customer_managed_key.key_vault_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_storage_account.this.identity[0].principal_id
}

# Re-encrypts the account with the customer-managed key. The key is
# pre-created by administrators in a purge-protected vault (e.g. the
# spoke's platform key vault), like the keys behind disk encryption
# sets.
resource "azurerm_storage_account_customer_managed_key" "this" {
  count = var.customer_managed_key == null ? 0 : 1

  storage_account_id = azurerm_storage_account.this.id
  key_vault_id       = var.customer_managed_key.key_vault_id
  key_name           = var.customer_managed_key.key_name
  key_version        = var.customer_managed_key.key_version

  depends_on = [azurerm_role_assignment.customer_managed_key]
}

# Containers and file shares are managed through the resource manager
# API so they can be created while the storage account only allows
# private data plane access. Containers are always private: anonymous
# access is disabled at the account level.
resource "azurerm_storage_container" "this" {
  #checkov:skip=CKV2_AZURE_21: The check wants the legacy azurerm_log_analytics_storage_insights resource, which reads the classic Storage Analytics logs with the account key - shared key authorisation is disabled here by default. Blob read, write and delete requests are logged through the blob service diagnostic setting instead.
  for_each = var.containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

# Azure file shares in the account.
resource "azurerm_storage_share" "this" {
  for_each = var.file_shares

  name               = each.key
  storage_account_id = azurerm_storage_account.this.id
  quota              = each.value.quota_in_gb
  access_tier        = each.value.access_tier
  enabled_protocol   = each.value.enabled_protocol
}

# Blob backup: the backup vault's identity is granted access to the
# account and the account's blob data is registered as a backup
# instance against the given policy.
resource "azurerm_role_assignment" "backup_vault" {
  count = var.backup == null ? 0 : 1

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Account Backup Contributor"
  principal_id         = var.backup.backup_vault_principal_id
}

# Registers the account's blob data against the backup policy.
resource "azurerm_data_protection_backup_instance_blob_storage" "this" {
  count = var.backup == null ? 0 : 1

  name               = var.name
  location           = var.location
  vault_id           = var.backup.backup_vault_id
  storage_account_id = azurerm_storage_account.this.id
  backup_policy_id   = var.backup.backup_policy_id

  depends_on = [azurerm_role_assignment.backup_vault]
}

# Sends blob service request logs and metrics to Log Analytics when a
# workspace is configured. Callers that create the workspace in the
# same apply must set enable_diagnostics themselves, because the
# workspace ID is unknown until apply and cannot decide the count.
resource "azurerm_monitor_diagnostic_setting" "blob" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.name}-blob"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}

# File service request logs and metrics, covering the SMB shares in
# file_shares - the reads, writes, deletes and authentication failures
# of workloads that mount them, such as FSLogix profile containers.
resource "azurerm_monitor_diagnostic_setting" "file" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.name}-file"
  target_resource_id         = "${azurerm_storage_account.this.id}/fileServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}

# Queue service request logs and metrics. The account's data plane is
# private, so queue logging comes from diagnostic settings rather than
# the classic Storage Analytics queue_properties, which are only
# settable through the data plane.
resource "azurerm_monitor_diagnostic_setting" "queue" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.name}-queue"
  target_resource_id         = "${azurerm_storage_account.this.id}/queueServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}

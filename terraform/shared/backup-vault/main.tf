terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A Data Protection backup vault with a default blob backup policy.
# Register storage accounts through the storage-account module's backup
# variable, passing this vault's ID, principal ID and policy ID.

resource "azurerm_data_protection_backup_vault" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  datastore_type      = "VaultStore"
  redundancy          = var.redundancy
  soft_delete         = "On"
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# The default blob backup policy storage accounts register against.
resource "azurerm_data_protection_backup_policy_blob_storage" "this" {
  name                                   = "${var.name}-blob"
  vault_id                               = azurerm_data_protection_backup_vault.this.id
  operational_default_retention_duration = var.blob_operational_retention_duration
}

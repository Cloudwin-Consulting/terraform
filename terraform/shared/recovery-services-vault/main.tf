terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A Recovery Services vault with a default daily virtual machine backup
# policy. Protect virtual machines through the virtual machine modules'
# backup variable, passing this vault's name, resource group and policy
# ID.

resource "azurerm_recovery_services_vault" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  storage_mode_type   = var.storage_mode_type
  soft_delete_enabled = true
  tags                = var.tags

  # Private by default: reach the vault through a private endpoint with
  # the AzureBackup subresource, resolved by the geo-specific
  # privatelink.<geo>.backup.windowsazure.com zone alongside the blob
  # and queue zones.
  public_network_access_enabled = var.public_network_access_enabled

  identity {
    type = "SystemAssigned"
  }
}

# The default daily backup policy virtual machines register against.
resource "azurerm_backup_policy_vm" "daily" {
  name                = "${var.name}-vm-daily"
  resource_group_name = var.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.this.name
  timezone            = var.backup_timezone

  backup {
    frequency = "Daily"
    time      = var.daily_backup_time
  }

  retention_daily {
    count = var.daily_retention_days
  }
}

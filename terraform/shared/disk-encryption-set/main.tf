terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A disk encryption set wrapping a customer-managed key held in a key
# vault, e.g. the spoke's platform key vault. The key is pre-created by
# administrators from inside the network (the vault's data plane is
# private); the vault must have purge protection enabled, which the
# key-vault module defaults to.
resource "azurerm_disk_encryption_set" "this" {
  name                      = var.name
  resource_group_name       = var.resource_group_name
  location                  = var.location
  key_vault_key_id          = var.key_vault_key_id
  auto_key_rotation_enabled = var.auto_key_rotation_enabled
  tags                      = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# The set's identity needs to wrap and unwrap the key in the vault.
resource "azurerm_role_assignment" "key_vault_crypto" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_disk_encryption_set.this.identity[0].principal_id
}

output "id" {
  description = "The ID of the backup vault."
  value       = azurerm_data_protection_backup_vault.this.id
}

output "name" {
  description = "The name of the backup vault."
  value       = azurerm_data_protection_backup_vault.this.name
}

output "principal_id" {
  description = "The principal ID of the backup vault's system-assigned managed identity."
  value       = azurerm_data_protection_backup_vault.this.identity[0].principal_id
}

output "blob_backup_policy_id" {
  description = "The ID of the default blob backup policy."
  value       = azurerm_data_protection_backup_policy_blob_storage.this.id
}

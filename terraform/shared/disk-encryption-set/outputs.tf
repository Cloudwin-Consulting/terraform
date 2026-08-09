output "id" {
  description = "The ID of the disk encryption set, for os_disk and data disk disk_encryption_set_id inputs."
  value       = azurerm_disk_encryption_set.this.id

  # Consumers block on the wrap/unwrap grant, so a disk never requests
  # its key before the set is allowed to use it.
  depends_on = [azurerm_role_assignment.key_vault_crypto]
}

output "name" {
  description = "The name of the disk encryption set."
  value       = azurerm_disk_encryption_set.this.name
}

output "principal_id" {
  description = "The principal ID of the set's system-assigned managed identity."
  value       = azurerm_disk_encryption_set.this.identity[0].principal_id
}

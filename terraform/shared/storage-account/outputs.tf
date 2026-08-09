output "id" {
  description = "The ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "The name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "primary_blob_endpoint" {
  description = "The primary blob service endpoint."
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "principal_id" {
  description = "The principal ID of the storage account's system-assigned managed identity."
  value       = azurerm_storage_account.this.identity[0].principal_id
}

output "container_ids" {
  description = "Map of container name to container ID."
  value       = { for name, container in azurerm_storage_container.this : name => container.id }
}

output "file_share_ids" {
  description = "Map of file share name to file share ID."
  value       = { for name, share in azurerm_storage_share.this : name => share.id }
}

output "primary_file_endpoint" {
  description = "The primary file service endpoint."
  value       = azurerm_storage_account.this.primary_file_endpoint
}

output "primary_access_key" {
  description = "The primary access key of the storage account. Only usable when shared key access is enabled, e.g. for the Logic Apps runtime."
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}

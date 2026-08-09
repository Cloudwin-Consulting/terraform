output "id" {
  description = "The ID of the managed disk."
  value       = azurerm_managed_disk.this.id
}

output "name" {
  description = "The name of the managed disk."
  value       = azurerm_managed_disk.this.name
}

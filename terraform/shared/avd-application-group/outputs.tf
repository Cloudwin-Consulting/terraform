output "id" {
  description = "The ID of the application group, e.g. for workspace associations and Desktop Virtualization User role assignments."
  value       = azurerm_virtual_desktop_application_group.this.id
}

output "name" {
  description = "The name of the application group."
  value       = azurerm_virtual_desktop_application_group.this.name
}

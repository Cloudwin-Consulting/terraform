output "id" {
  description = "The ID of the application security group, for network interface associations and security rule references."
  value       = azurerm_application_security_group.this.id
}

output "name" {
  description = "The name of the application security group."
  value       = azurerm_application_security_group.this.name
}

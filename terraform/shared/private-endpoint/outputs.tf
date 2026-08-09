output "id" {
  description = "The ID of the private endpoint."
  value       = azurerm_private_endpoint.this.id
}

output "name" {
  description = "The name of the private endpoint."
  value       = azurerm_private_endpoint.this.name
}

output "private_ip_address" {
  description = "The private IP address allocated to the private endpoint."
  value       = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
}

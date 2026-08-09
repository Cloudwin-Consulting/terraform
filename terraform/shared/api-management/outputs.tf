output "id" {
  description = "The ID of the API Management instance."
  value       = azurerm_api_management.this.id
}

output "name" {
  description = "The name of the API Management instance."
  value       = azurerm_api_management.this.name
}

output "gateway_url" {
  description = "The gateway URL of the instance. Resolves to a private address in internal mode."
  value       = azurerm_api_management.this.gateway_url
}

output "private_ip_addresses" {
  description = "The private IP addresses of the instance in internal mode."
  value       = azurerm_api_management.this.private_ip_addresses
}

output "principal_id" {
  description = "The principal ID of the instance's system-assigned managed identity."
  value       = azurerm_api_management.this.identity[0].principal_id
}

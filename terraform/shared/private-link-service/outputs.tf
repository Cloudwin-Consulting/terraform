output "id" {
  description = "The ID of the private link service. Consumers in the same tenant connect a private endpoint to it by ID."
  value       = azurerm_private_link_service.this.id
}

output "name" {
  description = "The name of the private link service."
  value       = azurerm_private_link_service.this.name
}

output "alias" {
  description = "The globally unique alias of the private link service. Consumers that only hold the alias connect with it instead of the ID."
  value       = azurerm_private_link_service.this.alias
}

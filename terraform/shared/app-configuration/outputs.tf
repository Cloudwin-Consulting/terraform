output "id" {
  description = "The ID of the App Configuration store."
  value       = azurerm_app_configuration.this.id
}

output "name" {
  description = "The name of the App Configuration store."
  value       = azurerm_app_configuration.this.name
}

output "endpoint" {
  description = "The endpoint of the App Configuration store. Resolves to the private endpoint from inside the network."
  value       = azurerm_app_configuration.this.endpoint
}

output "principal_id" {
  description = "The principal ID of the store's system-assigned managed identity."
  value       = azurerm_app_configuration.this.identity[0].principal_id
}

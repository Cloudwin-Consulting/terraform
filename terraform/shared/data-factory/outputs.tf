output "id" {
  description = "The ID of the data factory."
  value       = azurerm_data_factory.this.id
}

output "name" {
  description = "The name of the data factory."
  value       = azurerm_data_factory.this.name
}

output "principal_id" {
  description = "The principal ID of the factory's system-assigned managed identity. Grant it the data roles its linked services need, e.g. Storage Blob Data Contributor."
  value       = azurerm_data_factory.this.identity[0].principal_id
}

output "tenant_id" {
  description = "The tenant ID of the factory's system-assigned managed identity."
  value       = azurerm_data_factory.this.identity[0].tenant_id
}

output "integration_runtime_ids" {
  description = "The IDs of the Azure integration runtimes, keyed by runtime name."
  value       = { for name, runtime in azurerm_data_factory_integration_runtime_azure.this : name => runtime.id }
}

output "managed_private_endpoint_ids" {
  description = "The IDs of the managed private endpoints, keyed by endpoint name. Each connection must be approved on its target resource."
  value       = { for name, endpoint in azurerm_data_factory_managed_private_endpoint.this : name => endpoint.id }
}

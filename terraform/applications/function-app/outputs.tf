output "resource_group_name" {
  description = "The name of the application resource group."
  value       = azurerm_resource_group.this.name
}

output "function_app_name" {
  description = "The name of the function app."
  value       = module.function_app.function_app_name
}

output "function_app_default_hostname" {
  description = "The default hostname of the function app. Resolves to the private endpoint from inside the network."
  value       = module.function_app.default_hostname
}

output "function_app_principal_id" {
  description = "The principal ID of the function app's system-assigned managed identity."
  value       = module.function_app.principal_id
}

output "service_bus_namespace" {
  description = "The name of the Service Bus namespace."
  value       = module.service_bus.name
}

output "storage_account_name" {
  description = "The name of the runtime storage account."
  value       = module.storage.name
}

output "key_vault_name" {
  description = "The name of the application key vault."
  value       = module.key_vault.name
}

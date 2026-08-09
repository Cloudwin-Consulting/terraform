output "resource_group_name" {
  description = "The name of the application resource group."
  value       = azurerm_resource_group.this.name
}

output "logic_app_name" {
  description = "The name of the logic app."
  value       = module.logic_app.logic_app_name
}

output "logic_app_default_hostname" {
  description = "The default hostname of the logic app. Resolves to the private endpoint from inside the network."
  value       = module.logic_app.default_hostname
}

output "logic_app_principal_id" {
  description = "The principal ID of the logic app's system-assigned managed identity."
  value       = module.logic_app.principal_id
}

output "storage_account_name" {
  description = "The name of the runtime storage account."
  value       = module.storage.name
}

output "key_vault_name" {
  description = "The name of the application key vault."
  value       = module.key_vault.name
}

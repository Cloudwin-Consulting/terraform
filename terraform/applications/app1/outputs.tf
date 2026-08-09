output "resource_group_name" {
  description = "The name of the application resource group."
  value       = azurerm_resource_group.this.name
}

output "web_app_name" {
  description = "The name of the web app."
  value       = module.app_service.web_app_name
}

output "web_app_default_hostname" {
  description = "The default hostname of the web app. Resolves to the private endpoint from inside the network."
  value       = module.app_service.default_hostname
}

output "web_app_principal_id" {
  description = "The principal ID of the web app's system-assigned managed identity."
  value       = module.app_service.principal_id
}

output "storage_account_name" {
  description = "The name of the application storage account."
  value       = module.storage.name
}

output "key_vault_name" {
  description = "The name of the application key vault."
  value       = module.key_vault.name
}

output "key_vault_uri" {
  description = "The URI of the application key vault. Resolves to the private endpoint from inside the network."
  value       = module.key_vault.vault_uri
}

output "front_door_endpoint_host_name" {
  description = "The hostname of the app's Front Door endpoint, if deployed."
  value       = var.enable_front_door_endpoint ? module.front_door_endpoint[0].host_name : null
}

output "traffic_manager_fqdn" {
  description = "The fully qualified domain name of the Traffic Manager profile, if deployed."
  value       = var.enable_traffic_manager ? module.traffic_manager[0].fqdn : null
}

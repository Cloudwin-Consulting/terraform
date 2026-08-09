output "resource_group_name" {
  description = "The name of the application resource group."
  value       = azurerm_resource_group.this.name
}

output "container_app_environment_default_domain" {
  description = "The default domain of the container app environment."
  value       = module.container_app_environment.default_domain
}

output "container_app_fqdn" {
  description = "The fully qualified domain name of the container app. Resolves to the environment's private load balancer from inside the network."
  value       = module.container_app.latest_revision_fqdn
}

output "container_app_principal_id" {
  description = "The principal ID of the container app's system-assigned managed identity."
  value       = module.container_app.principal_id
}

output "container_registry_login_server" {
  description = "The login server of the container registry."
  value       = module.container_registry.login_server
}

output "key_vault_name" {
  description = "The name of the application key vault."
  value       = module.key_vault.name
}

output "key_vault_uri" {
  description = "The URI of the application key vault. Resolves to the private endpoint from inside the network."
  value       = module.key_vault.vault_uri
}

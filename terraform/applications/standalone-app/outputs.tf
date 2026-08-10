output "resource_group_name" {
  description = "The name of the application resource group, which holds every resource in this stack."
  value       = azurerm_resource_group.this.name
}

output "virtual_network_id" {
  description = "The ID of the application's virtual network. Hand this to the platform team when the hub peers to it."
  value       = module.vnet.id
}

output "virtual_network_name" {
  description = "The name of the application's virtual network."
  value       = module.vnet.name
}

output "subnet_ids" {
  description = "Map of subnet name to subnet ID."
  value       = module.vnet.subnet_ids
}

output "private_dns_zone_ids" {
  description = "Map of private DNS zone name to zone ID, covering both the zones this stack created and any supplied through existing_private_dns_zone_ids. Empty entries mean the endpoints were created without a zone group."
  value       = local.private_dns_zone_ids
}

output "linux_virtual_machine_names" {
  description = "The names of the Linux web tier machines."
  value       = module.linux_virtual_machine[*].name
}

output "linux_virtual_machine_private_ip_addresses" {
  description = "The private IP addresses of the Linux web tier machines. Connect over the management network."
  value       = module.linux_virtual_machine[*].private_ip_address
}

output "windows_virtual_machine_names" {
  description = "The names of the Windows application tier machines."
  value       = module.windows_virtual_machine[*].name
}

output "windows_virtual_machine_private_ip_addresses" {
  description = "The private IP addresses of the Windows application tier machines. Connect over the management network."
  value       = module.windows_virtual_machine[*].private_ip_address
}

output "windows_virtual_machine_admin_passwords" {
  description = "The generated Windows admin passwords, keyed by machine name. They live in the state file alone, which is why the pipelines for this stack publish no decodable plans."
  value       = { for index in range(var.windows_virtual_machine_count) : module.windows_virtual_machine[index].name => random_password.windows_admin[index].result }
  sensitive   = true
}

output "recovery_services_vault_name" {
  description = "The name of the Recovery Services vault protecting the virtual machines, if deployed."
  value       = var.enable_backup ? module.recovery_services_vault[0].name : null
}

output "sql_server_names" {
  description = "The names of the SQL servers."
  value       = module.sql_server[*].name
}

output "sql_server_fqdns" {
  description = "The fully qualified domain names of the SQL servers. Each resolves to its private endpoint from inside the network."
  value       = module.sql_server[*].fully_qualified_domain_name
}

output "sql_database_ids" {
  description = "Map of database name to database ID, per SQL server in deployment order."
  value       = module.sql_server[*].database_ids
}

output "key_vault_name" {
  description = "The name of the application key vault."
  value       = module.key_vault.name
}

output "key_vault_uri" {
  description = "The URI of the application key vault. Resolves to the private endpoint from inside the network."
  value       = module.key_vault.vault_uri
}

output "storage_account_name" {
  description = "The name of the application storage account."
  value       = module.storage.name
}

output "log_analytics_workspace_id" {
  description = "The ID of the application's Log Analytics workspace."
  value       = module.log_analytics.id
}

output "application_insights_connection_string" {
  description = "The connection string applications use to send telemetry to this application's Application Insights component."
  value       = module.application_insights.connection_string
  sensitive   = true
}

output "web_app_name" {
  description = "The name of the web app, if deployed."
  value       = var.enable_app_service ? module.app_service[0].web_app_name : null
}

output "web_app_default_hostname" {
  description = "The default hostname of the web app, if deployed. Resolves to its private endpoint from inside the network."
  value       = var.enable_app_service ? module.app_service[0].default_hostname : null
}

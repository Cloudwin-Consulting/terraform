output "resource_group_name" {
  description = "The name of the application resource group."
  value       = azurerm_resource_group.this.name
}

output "sql_server_name" {
  description = "The name of the SQL server."
  value       = module.sql_server.name
}

output "sql_server_fqdn" {
  description = "The fully qualified domain name of the SQL server. Resolves to the private endpoint from inside the network."
  value       = module.sql_server.fully_qualified_domain_name
}

output "database_ids" {
  description = "Map of database name to database ID."
  value       = module.sql_server.database_ids
}

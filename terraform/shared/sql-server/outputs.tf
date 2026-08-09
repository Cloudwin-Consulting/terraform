output "id" {
  description = "The ID of the SQL server."
  value       = azurerm_mssql_server.this.id
}

output "name" {
  description = "The name of the SQL server."
  value       = azurerm_mssql_server.this.name
}

output "fully_qualified_domain_name" {
  description = "The fully qualified domain name of the SQL server. Resolves to the private endpoint from inside the network."
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "principal_id" {
  description = "The principal ID of the SQL server's system-assigned managed identity."
  value       = azurerm_mssql_server.this.identity[0].principal_id
}

output "database_ids" {
  description = "Map of database name to database ID."
  value       = { for name, database in azurerm_mssql_database.this : name => database.id }
}

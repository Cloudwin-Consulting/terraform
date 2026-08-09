output "id" {
  description = "The ID of the MySQL flexible server."
  value       = azurerm_mysql_flexible_server.this.id
}

output "name" {
  description = "The name of the MySQL flexible server."
  value       = azurerm_mysql_flexible_server.this.name
}

output "fqdn" {
  description = "The fully qualified domain name of the server."
  value       = azurerm_mysql_flexible_server.this.fqdn
}

output "database_names" {
  description = "The names of the databases on the server."
  value       = [for database in azurerm_mysql_flexible_database.this : database.name]
}

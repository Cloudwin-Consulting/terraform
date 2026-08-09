output "id" {
  description = "The ID of the SQL managed instance."
  value       = azurerm_mssql_managed_instance.this.id
}

output "name" {
  description = "The name of the SQL managed instance."
  value       = azurerm_mssql_managed_instance.this.name
}

output "fqdn" {
  description = "The fully qualified domain name of the SQL managed instance."
  value       = azurerm_mssql_managed_instance.this.fqdn
}

output "principal_id" {
  description = "The principal ID of the instance's system-assigned managed identity."
  value       = azurerm_mssql_managed_instance.this.identity[0].principal_id
}

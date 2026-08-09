output "id" {
  description = "The ID of the Cosmos DB account."
  value       = azurerm_cosmosdb_account.this.id
}

output "name" {
  description = "The name of the Cosmos DB account."
  value       = azurerm_cosmosdb_account.this.name
}

output "endpoint" {
  description = "The endpoint of the Cosmos DB account. Resolves to the private endpoint from inside the network."
  value       = azurerm_cosmosdb_account.this.endpoint
}

output "principal_id" {
  description = "The principal ID of the account's system-assigned managed identity."
  value       = azurerm_cosmosdb_account.this.identity[0].principal_id
}

output "sql_database_ids" {
  description = "Map of SQL database name to database ID."
  value       = { for name, database in azurerm_cosmosdb_sql_database.this : name => database.id }
}

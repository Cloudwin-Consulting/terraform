output "id" {
  description = "The ID of the search service."
  value       = azurerm_search_service.this.id
}

output "name" {
  description = "The name of the search service."
  value       = azurerm_search_service.this.name
}

output "endpoint" {
  description = "The endpoint queries and indexing calls are sent to. Resolves to the private endpoint from inside the network."
  value       = "https://${azurerm_search_service.this.name}.search.windows.net"
}

output "principal_id" {
  description = "The principal ID of the service's system-assigned managed identity, which indexers and skillsets connect out with. Grant it the data roles they need, e.g. Storage Blob Data Reader on an indexed account. Null on the free SKU, which supports no managed identity."
  value       = try(azurerm_search_service.this.identity[0].principal_id, null)
}

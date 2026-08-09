output "id" {
  description = "The ID of the Event Hubs namespace."
  value       = azurerm_eventhub_namespace.this.id
}

output "name" {
  description = "The name of the Event Hubs namespace."
  value       = azurerm_eventhub_namespace.this.name
}

output "principal_id" {
  description = "The principal ID of the namespace's system-assigned managed identity."
  value       = azurerm_eventhub_namespace.this.identity[0].principal_id
}

output "event_hub_ids" {
  description = "Map of event hub name to event hub ID."
  value       = { for name, hub in azurerm_eventhub.this : name => hub.id }
}

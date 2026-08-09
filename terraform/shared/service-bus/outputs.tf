output "id" {
  description = "The ID of the Service Bus namespace."
  value       = azurerm_servicebus_namespace.this.id
}

output "name" {
  description = "The name of the Service Bus namespace."
  value       = azurerm_servicebus_namespace.this.name
}

output "endpoint" {
  description = "The endpoint of the Service Bus namespace."
  value       = azurerm_servicebus_namespace.this.endpoint
}

output "principal_id" {
  description = "The principal ID of the namespace's system-assigned managed identity."
  value       = azurerm_servicebus_namespace.this.identity[0].principal_id
}

output "queue_ids" {
  description = "Map of queue name to queue ID."
  value       = { for name, queue in azurerm_servicebus_queue.this : name => queue.id }
}

output "topic_ids" {
  description = "Map of topic name to topic ID."
  value       = { for name, topic in azurerm_servicebus_topic.this : name => topic.id }
}

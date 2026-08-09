output "id" {
  description = "The ID of the Event Grid topic."
  value       = azurerm_eventgrid_topic.this.id
}

output "name" {
  description = "The name of the Event Grid topic."
  value       = azurerm_eventgrid_topic.this.name
}

output "endpoint" {
  description = "The endpoint publishers post events to. Resolves to the private endpoint from inside the network."
  value       = azurerm_eventgrid_topic.this.endpoint
}

output "principal_id" {
  description = "The principal ID of the topic's system-assigned managed identity, which deliveries are made with. Grant it the destination's data role, e.g. Azure Event Hubs Data Sender."
  value       = azurerm_eventgrid_topic.this.identity[0].principal_id
}

output "event_subscription_ids" {
  description = "The IDs of the event subscriptions, keyed by subscription name."
  value       = { for name, subscription in azurerm_eventgrid_event_subscription.this : name => subscription.id }
}

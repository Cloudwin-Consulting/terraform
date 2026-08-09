output "id" {
  description = "The ID of the container app."
  value       = azurerm_container_app.this.id
}

output "name" {
  description = "The name of the container app."
  value       = azurerm_container_app.this.name
}

output "latest_revision_fqdn" {
  description = "The fully qualified domain name of the latest revision. Resolves to the environment's private load balancer on an internal environment."
  value       = azurerm_container_app.this.latest_revision_fqdn
}

output "principal_id" {
  description = "The principal ID of the container app's system-assigned managed identity."
  value       = azurerm_container_app.this.identity[0].principal_id
}

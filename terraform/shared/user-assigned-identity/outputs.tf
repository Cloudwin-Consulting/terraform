output "id" {
  description = "The ID of the user-assigned identity."
  value       = azurerm_user_assigned_identity.this.id
}

output "name" {
  description = "The name of the user-assigned identity."
  value       = azurerm_user_assigned_identity.this.name
}

output "principal_id" {
  description = "The principal ID of the identity, for role assignments."
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "client_id" {
  description = "The client ID of the identity, for workloads authenticating with it."
  value       = azurerm_user_assigned_identity.this.client_id
}

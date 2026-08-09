output "id" {
  description = "The ID of the host pool."
  value       = azurerm_virtual_desktop_host_pool.this.id
}

output "name" {
  description = "The name of the host pool."
  value       = azurerm_virtual_desktop_host_pool.this.name
}

output "registration_token" {
  description = "The registration token session hosts join the pool with, e.g. for the avd-session-host module. Rotates every registration_token_rotation_days."
  value       = azurerm_virtual_desktop_host_pool_registration_info.this.token
  sensitive   = true
}

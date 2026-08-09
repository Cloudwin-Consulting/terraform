output "id" {
  description = "The ID of the firewall policy."
  value       = azurerm_firewall_policy.this.id
}

output "name" {
  description = "The name of the firewall policy."
  value       = azurerm_firewall_policy.this.name
}

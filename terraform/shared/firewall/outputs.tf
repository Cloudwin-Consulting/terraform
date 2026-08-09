output "id" {
  description = "The ID of the firewall."
  value       = azurerm_firewall.this.id
}

output "name" {
  description = "The name of the firewall."
  value       = azurerm_firewall.this.name
}

output "private_ip_address" {
  description = "The private IP address of the firewall, used as the next hop in route tables."
  value       = azurerm_firewall.this.ip_configuration[0].private_ip_address
}

output "public_ip_address" {
  description = "The public IP address of the firewall."
  value       = azurerm_public_ip.this.ip_address
}

output "policy_id" {
  description = "The ID of the firewall policy. Attach rule collection groups to this."
  value       = module.policy.id
}

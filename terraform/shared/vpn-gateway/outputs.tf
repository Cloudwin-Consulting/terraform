output "id" {
  description = "The ID of the VPN gateway."
  value       = azurerm_virtual_network_gateway.this.id
}

output "name" {
  description = "The name of the VPN gateway."
  value       = azurerm_virtual_network_gateway.this.name
}

output "public_ip_address" {
  description = "The public IP address VPN connections terminate on."
  value       = azurerm_public_ip.this.ip_address
}

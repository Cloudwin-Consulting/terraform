output "id" {
  description = "The ID of the application gateway."
  value       = azurerm_application_gateway.this.id
}

output "name" {
  description = "The name of the application gateway."
  value       = azurerm_application_gateway.this.name
}

output "private_ip_address" {
  description = "The private IP address of the internal frontend the listener binds to."
  value       = var.private_ip_address
}

output "public_ip_address" {
  description = "The public IP address the v2 SKU requires. Nothing listens on it."
  value       = azurerm_public_ip.this.ip_address
}

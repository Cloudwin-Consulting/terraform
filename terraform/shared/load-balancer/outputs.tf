output "id" {
  description = "The ID of the load balancer."
  value       = azurerm_lb.this.id
}

output "name" {
  description = "The name of the load balancer."
  value       = azurerm_lb.this.name
}

output "backend_address_pool_id" {
  description = "The ID of the backend address pool to associate network interfaces with."
  value       = azurerm_lb_backend_address_pool.this.id
}

output "private_ip_address" {
  description = "The private IP address of the load balancer frontend, or null when public_ip_enabled is set."
  value       = var.public_ip_enabled ? null : one(azurerm_lb.this.frontend_ip_configuration[*].private_ip_address)
}

output "public_ip_address" {
  description = "The public IP address of the load balancer frontend, or null when public_ip_enabled is false."
  value       = one(azurerm_public_ip.this[*].ip_address)
}

output "public_ip_id" {
  description = "The ID of the public IP of the load balancer frontend, or null when public_ip_enabled is false."
  value       = one(azurerm_public_ip.this[*].id)
}

output "frontend_ip_address" {
  description = "The address the load balancer answers on, private or public depending on public_ip_enabled."
  value       = var.public_ip_enabled ? one(azurerm_public_ip.this[*].ip_address) : one(azurerm_lb.this.frontend_ip_configuration[*].private_ip_address)
}

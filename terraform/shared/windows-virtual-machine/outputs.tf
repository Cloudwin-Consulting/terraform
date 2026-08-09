output "id" {
  description = "The ID of the virtual machine."
  value       = azurerm_windows_virtual_machine.this.id
}

output "name" {
  description = "The name of the virtual machine."
  value       = azurerm_windows_virtual_machine.this.name
}

output "private_ip_address" {
  description = "The private IP address of the virtual machine."
  value       = azurerm_network_interface.this.private_ip_address
}

output "principal_id" {
  description = "The principal ID of the virtual machine's system-assigned managed identity."
  value       = azurerm_windows_virtual_machine.this.identity[0].principal_id
}

output "network_interface_id" {
  description = "The ID of the virtual machine's network interface, e.g. for load balancer backend pool associations."
  value       = azurerm_network_interface.this.id
}

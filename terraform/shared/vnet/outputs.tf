output "id" {
  description = "The ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "name" {
  description = "The name of the virtual network."
  value       = azurerm_virtual_network.this.name
}

output "address_space" {
  description = "The address space of the virtual network."
  value       = azurerm_virtual_network.this.address_space
}

output "subnet_ids" {
  description = "Map of subnet name to subnet ID."
  value       = { for name, subnet in azurerm_subnet.this : name => subnet.id }
}

output "subnet_address_prefixes" {
  description = "Map of subnet name to its address prefixes."
  value       = { for name, subnet in azurerm_subnet.this : name => subnet.address_prefixes }
}

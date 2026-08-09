output "resource_group_name" {
  description = "The name of the example's resource group."
  value       = azurerm_resource_group.this.name
}

output "virtual_network_name" {
  description = "The name of the example's own virtual network."
  value       = module.vnet.name
}

output "application_gateway_name" {
  description = "The name of the application gateway."
  value       = module.application_gateway.name
}

output "application_gateway_private_ip_address" {
  description = "The private address of the gateway's internal frontend - the address a firewall DNAT rule or DNS record publishing this gateway must name."
  value       = module.application_gateway.private_ip_address
}

output "application_gateway_public_ip_address" {
  description = "The public address the v2 SKU requires. Nothing listens on it: the only listener binds to the private frontend."
  value       = module.application_gateway.public_ip_address
}

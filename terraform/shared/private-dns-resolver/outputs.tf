output "id" {
  description = "The ID of the DNS private resolver."
  value       = azurerm_private_dns_resolver.this.id
}

output "name" {
  description = "The name of the DNS private resolver."
  value       = azurerm_private_dns_resolver.this.name
}

output "inbound_endpoint_ip_address" {
  description = "The IP address of the inbound endpoint. Point external DNS forwarders at this address."
  value       = azurerm_private_dns_resolver_inbound_endpoint.this.ip_configurations[0].private_ip_address
}

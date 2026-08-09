output "id" {
  description = "The ID of the NAT gateway."
  value       = azurerm_nat_gateway.this.id
}

output "public_ip_address" {
  description = "The public IP address outbound flows translate to, e.g. for allow-listing with external providers."
  value       = azurerm_public_ip.this.ip_address
}

output "id" {
  description = "The ID of the endpoint."
  value       = azurerm_cdn_frontdoor_endpoint.this.id
}

output "host_name" {
  description = "The hostname of the endpoint, e.g. example-abc.z01.azurefd.net."
  value       = azurerm_cdn_frontdoor_endpoint.this.host_name
}

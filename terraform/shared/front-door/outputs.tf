output "id" {
  description = "The ID of the Front Door profile."
  value       = azurerm_cdn_frontdoor_profile.this.id
}

output "name" {
  description = "The name of the Front Door profile."
  value       = azurerm_cdn_frontdoor_profile.this.name
}

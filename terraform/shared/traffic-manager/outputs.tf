output "id" {
  description = "The ID of the Traffic Manager profile."
  value       = azurerm_traffic_manager_profile.this.id
}

output "name" {
  description = "The name of the Traffic Manager profile."
  value       = azurerm_traffic_manager_profile.this.name
}

output "fqdn" {
  description = "The fully qualified domain name of the profile, e.g. example.trafficmanager.net."
  value       = azurerm_traffic_manager_profile.this.fqdn
}

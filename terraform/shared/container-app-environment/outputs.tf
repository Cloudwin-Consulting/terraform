output "id" {
  description = "The ID of the container app environment."
  value       = azurerm_container_app_environment.this.id
}

output "name" {
  description = "The name of the container app environment."
  value       = azurerm_container_app_environment.this.name
}

output "default_domain" {
  description = "The default domain of the environment, e.g. example.uksouth.azurecontainerapps.io."
  value       = azurerm_container_app_environment.this.default_domain
}

output "static_ip_address" {
  description = "The IP address of the environment's ingress load balancer. Private when the internal load balancer is enabled."
  value       = azurerm_container_app_environment.this.static_ip_address
}

output "resource_group_name" {
  description = "The name of the example's resource group."
  value       = azurerm_resource_group.this.name
}

output "front_door_profile_id" {
  description = "The ID of the Front Door profile. Pass it to the front-door-endpoint module to add an application's own endpoint to this profile."
  value       = module.front_door.id
}

output "front_door_profile_name" {
  description = "The name of the Front Door profile."
  value       = module.front_door.name
}

output "endpoint_host_names" {
  description = "The hostnames of the endpoints, keyed by their role name. Each resolves and serves TLS immediately; each answers 503 until its placeholder origin is replaced with a real one."
  value       = { for name, endpoint in module.front_door_endpoint : name => endpoint.host_name }
}

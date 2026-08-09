output "resource_group_name" {
  description = "The name of the example's resource group."
  value       = azurerm_resource_group.this.name
}

output "traffic_manager_name" {
  description = "The name of the Traffic Manager profile."
  value       = module.traffic_manager.name
}

output "traffic_manager_fqdn" {
  description = "The fully qualified domain name clients resolve, e.g. traffic-manager-example-dev.trafficmanager.net. It answers with a placeholder endpoint until the targets are replaced with real ones."
  value       = module.traffic_manager.fqdn
}

output "resource_group_name" {
  description = "The name of the monitoring spoke's core resource group, holding the workspace, its private link scope, Application Insights and the log archive."
  value       = azurerm_resource_group.this.name
}

output "network_resource_group_name" {
  description = "The name of the monitoring spoke's network resource group, holding the virtual network and its network security group."
  value       = azurerm_resource_group.network.name
}

output "dns_resource_group_name" {
  description = "The name of the monitoring spoke's DNS resource group, for private DNS zones the spoke owns."
  value       = azurerm_resource_group.dns.name
}

output "secrets_resource_group_name" {
  description = "The name of the monitoring spoke's secrets resource group, holding the platform key vault, if deployed."
  value       = var.enable_platform_key_vault ? azurerm_resource_group.secrets[0].name : null
}

output "virtual_network_id" {
  description = "The ID of the monitoring spoke virtual network, if deployed."
  value       = local.vnet_id
}

output "virtual_network_name" {
  description = "The name of the monitoring spoke virtual network, if deployed."
  value       = var.enable_virtual_network ? module.vnet[0].name : null
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace, if deployed."
  value       = var.enable_log_analytics ? module.log_analytics[0].id : null
}

output "data_collection_endpoint_id" {
  description = "The ID of the data collection endpoint agents use for private configuration access and ingestion, if deployed."
  value       = var.enable_log_analytics ? azurerm_monitor_data_collection_endpoint.this[0].id : null
}

output "log_analytics_workspace_name" {
  description = "The name of the Log Analytics workspace, if deployed."
  value       = var.enable_log_analytics ? module.log_analytics[0].name : null
}

output "application_insights_name" {
  description = "The name of the Application Insights component, if deployed."
  value       = var.enable_application_insights ? module.application_insights[0].name : null
}

output "application_insights_connection_string" {
  description = "The connection string applications use to send telemetry, if Application Insights is deployed."
  value       = var.enable_application_insights ? module.application_insights[0].connection_string : null
  sensitive   = true
}

output "log_archive_storage_account_name" {
  description = "The name of the log archive storage account, if deployed."
  value       = var.enable_log_archive_storage ? module.log_archive_storage[0].name : null
}

output "platform_key_vault_name" {
  description = "The name of the spoke's platform key vault, if deployed. Pre-load secrets for monitoring deployments here."
  value       = var.enable_platform_key_vault ? module.platform_key_vault[0].name : null
}

output "platform_key_vault_uri" {
  description = "The URI of the spoke's platform key vault, if deployed. Use it in key vault references."
  value       = var.enable_platform_key_vault ? module.platform_key_vault[0].vault_uri : null
}

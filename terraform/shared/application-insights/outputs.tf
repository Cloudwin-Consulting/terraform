output "id" {
  description = "The ID of the Application Insights component."
  value       = azurerm_application_insights.this.id
}

output "name" {
  description = "The name of the Application Insights component."
  value       = azurerm_application_insights.this.name
}

output "app_id" {
  description = "The App ID of the Application Insights component."
  value       = azurerm_application_insights.this.app_id
}

output "connection_string" {
  description = "The connection string applications use to send telemetry."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

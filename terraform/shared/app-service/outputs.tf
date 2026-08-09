output "service_plan_id" {
  description = "The ID of the App Service plan."
  value       = azurerm_service_plan.this.id
}

output "web_app_id" {
  description = "The ID of the web app."
  value       = azurerm_linux_web_app.this.id
}

output "web_app_name" {
  description = "The name of the web app."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "The default hostname of the web app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "principal_id" {
  description = "The principal ID of the web app's system-assigned managed identity."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

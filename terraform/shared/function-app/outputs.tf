output "service_plan_id" {
  description = "The ID of the App Service plan."
  value       = azurerm_service_plan.this.id
}

output "function_app_id" {
  description = "The ID of the function app."
  value       = azurerm_linux_function_app.this.id
}

output "function_app_name" {
  description = "The name of the function app."
  value       = azurerm_linux_function_app.this.name
}

output "default_hostname" {
  description = "The default hostname of the function app."
  value       = azurerm_linux_function_app.this.default_hostname
}

output "principal_id" {
  description = "The principal ID of the function app's system-assigned managed identity."
  value       = azurerm_linux_function_app.this.identity[0].principal_id
}

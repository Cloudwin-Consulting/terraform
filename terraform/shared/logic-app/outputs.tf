output "service_plan_id" {
  description = "The ID of the Workflow Standard plan."
  value       = azurerm_service_plan.this.id
}

output "logic_app_id" {
  description = "The ID of the logic app."
  value       = azurerm_logic_app_standard.this.id
}

output "logic_app_name" {
  description = "The name of the logic app."
  value       = azurerm_logic_app_standard.this.name
}

output "default_hostname" {
  description = "The default hostname of the logic app."
  value       = azurerm_logic_app_standard.this.default_hostname
}

output "principal_id" {
  description = "The principal ID of the logic app's system-assigned managed identity."
  value       = azurerm_logic_app_standard.this.identity[0].principal_id
}

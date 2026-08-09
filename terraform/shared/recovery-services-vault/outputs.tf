output "id" {
  description = "The ID of the Recovery Services vault."
  value       = azurerm_recovery_services_vault.this.id
}

output "name" {
  description = "The name of the Recovery Services vault."
  value       = azurerm_recovery_services_vault.this.name
}

output "resource_group_name" {
  description = "The resource group of the Recovery Services vault."
  value       = azurerm_recovery_services_vault.this.resource_group_name
}

output "daily_backup_policy_id" {
  description = "The ID of the default daily virtual machine backup policy."
  value       = azurerm_backup_policy_vm.daily.id
}

output "action_group_id" {
  description = "The ID of the action group, for use in additional alert rules."
  value       = azurerm_monitor_action_group.this.id
}

output "action_group_name" {
  description = "The name of the action group."
  value       = azurerm_monitor_action_group.this.name
}

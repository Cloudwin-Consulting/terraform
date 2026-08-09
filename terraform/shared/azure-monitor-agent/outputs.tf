output "extension_id" {
  description = "The ID of the agent extension."
  value       = azurerm_virtual_machine_extension.this.id
}

output "data_collection_rule_id" {
  description = "The ID of the associated data collection rule."
  value       = local.data_collection_rule_id
}

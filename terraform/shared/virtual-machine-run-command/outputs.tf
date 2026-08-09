output "id" {
  description = "The ID of the run command resource."
  value       = azurerm_virtual_machine_run_command.this.id
}

output "name" {
  description = "The name of the run command resource."
  value       = azurerm_virtual_machine_run_command.this.name
}

output "id" {
  description = "The ID of the Automation account."
  value       = azurerm_automation_account.this.id
}

output "name" {
  description = "The name of the Automation account."
  value       = azurerm_automation_account.this.name
}

output "principal_id" {
  description = "The principal ID of the account's system-assigned managed identity, which jobs run as. Grant it the roles the runbooks need on their targets."
  value       = azurerm_automation_account.this.identity[0].principal_id
}

output "dsc_server_endpoint" {
  description = "The DSC server endpoint of the account. Resolves to the private endpoint from inside the network."
  value       = azurerm_automation_account.this.dsc_server_endpoint
}

output "runbook_names" {
  description = "The names of the runbooks in the account."
  value       = [for name, runbook in azurerm_automation_runbook.this : runbook.name]
}

output "schedule_names" {
  description = "The names of the schedules in the account."
  value       = [for name, schedule in azurerm_automation_schedule.this : schedule.name]
}

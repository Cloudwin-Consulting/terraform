output "role_definition_id" {
  description = "The fully qualified ID of the role definition being managed."
  value       = local.role_definition_id
}

output "eligible_assignment_ids" {
  description = "The IDs of the eligible role assignments, keyed by the labels in eligible_principals."
  value       = { for label, assignment in azurerm_pim_eligible_role_assignment.this : label => assignment.id }
}

output "active_assignment_ids" {
  description = "The IDs of the active role assignments, keyed by the labels in active_principals."
  value       = { for label, assignment in azurerm_pim_active_role_assignment.this : label => assignment.id }
}

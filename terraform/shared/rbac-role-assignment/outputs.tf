output "ids" {
  description = "The IDs of the role assignments, keyed by the labels in principals."
  value       = { for label, assignment in azurerm_role_assignment.this : label => assignment.id }
}

output "principal_ids" {
  description = "The object IDs of the principals granted the role, keyed by the labels in principals."
  value       = { for label, assignment in azurerm_role_assignment.this : label => assignment.principal_id }
}

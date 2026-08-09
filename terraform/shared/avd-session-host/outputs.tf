output "id" {
  description = "The ID of the session host virtual machine."
  value       = module.virtual_machine.id
}

output "name" {
  description = "The name of the session host virtual machine."
  value       = module.virtual_machine.name
}

output "private_ip_address" {
  description = "The private IP address of the session host."
  value       = module.virtual_machine.private_ip_address
}

output "principal_id" {
  description = "The principal ID of the session host's system-assigned managed identity."
  value       = module.virtual_machine.principal_id
}

output "network_interface_id" {
  description = "The ID of the session host's network interface."
  value       = module.virtual_machine.network_interface_id
}

output "private_ip_address" {
  description = "The private IP address of the jump box, reached through Azure Bastion."
  value       = module.virtual_machine.private_ip_address
}

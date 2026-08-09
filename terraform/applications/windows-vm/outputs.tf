output "resource_group_name" {
  description = "The name of the application resource group."
  value       = azurerm_resource_group.this.name
}

output "virtual_machine_names" {
  description = "The names of the virtual machines."
  value       = module.virtual_machine[*].name
}

output "virtual_machine_private_ip_addresses" {
  description = "The private IP addresses of the virtual machines. Connect through Azure Bastion in the hub."
  value       = module.virtual_machine[*].private_ip_address
}

output "virtual_machine_principal_ids" {
  description = "The principal IDs of the virtual machines' system-assigned managed identities."
  value       = module.virtual_machine[*].principal_id
}

output "virtual_machine_admin_passwords" {
  description = "The generated admin passwords, keyed by virtual machine name. Empty when the password comes from the platform key vault."
  value       = var.admin_password_key_vault_secret == null ? { for i in range(var.virtual_machine_count) : module.virtual_machine[i].name => random_password.admin[i].result } : {}
  sensitive   = true
}

output "load_balancer_private_ip_address" {
  description = "The private IP address of the internal load balancer, if deployed."
  value       = var.enable_load_balancer ? module.load_balancer[0].private_ip_address : null
}

output "key_vault_name" {
  description = "The name of the application key vault."
  value       = module.key_vault.name
}

output "key_vault_uri" {
  description = "The URI of the application key vault. Resolves to the private endpoint from inside the network."
  value       = module.key_vault.vault_uri
}

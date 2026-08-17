output "resource_group_name" {
  description = "The name of the application resource group."
  value       = azurerm_resource_group.this.name
}

output "virtual_machine_names" {
  description = "The names of the SQL Server machines."
  value       = module.sql_server_virtual_machine[*].name
}

output "virtual_machine_private_ip_addresses" {
  description = "The private IP addresses of the SQL Server machines. Clients reach the instances here, on sql_connectivity_port; administrators connect through Azure Bastion in the hub."
  value       = module.sql_server_virtual_machine[*].private_ip_address
}

output "virtual_machine_principal_ids" {
  description = "The principal IDs of the machines' system-assigned managed identities."
  value       = module.sql_server_virtual_machine[*].principal_id
}

output "sql_virtual_machine_ids" {
  description = "The IDs of the SQL virtual machine registrations, e.g. to add the machines to an availability group listener."
  value       = module.sql_server_virtual_machine[*].sql_virtual_machine_id
}

output "data_disk_luns_by_role" {
  description = "The LUNs backing each storage role on each machine, as handed to the SQL IaaS Agent extension. Useful when extending a machine's storage later, because new disks must not reuse a LUN."
  value       = module.sql_server_virtual_machine[*].data_disk_luns_by_role
}

output "virtual_machine_admin_passwords" {
  description = "The generated local administrator passwords, keyed by machine name. Empty when the password comes from the platform key vault."
  value       = var.admin_password_key_vault_secret == null ? { for i in range(var.virtual_machine_count) : module.sql_server_virtual_machine[i].name => random_password.admin[i].result } : {}
  sensitive   = true
}

output "sql_login_passwords" {
  description = "The generated SQL login passwords, keyed by machine name. Empty unless enable_sql_authentication is set. Move these into a key vault and rotate them: they are only generated here so the deployment does not need a pre-loaded secret."
  value       = var.enable_sql_authentication ? { for i in range(var.virtual_machine_count) : module.sql_server_virtual_machine[i].name => random_password.sql_login[i].result } : {}
  sensitive   = true
}

output "key_vault_name" {
  description = "The name of the application key vault."
  value       = module.key_vault.name
}

output "key_vault_uri" {
  description = "The URI of the application key vault. Resolves to the private endpoint from inside the network."
  value       = module.key_vault.vault_uri
}

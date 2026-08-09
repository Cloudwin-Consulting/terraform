output "resource_group_name" {
  description = "The name of the AVD resource group."
  value       = azurerm_resource_group.this.name
}

output "host_pool_name" {
  description = "The name of the host pool."
  value       = module.host_pool.name
}

output "workspace_name" {
  description = "The name of the workspace users subscribe to from the AVD clients."
  value       = module.workspace.name
}

output "application_group_id" {
  description = "The ID of the desktop application group, e.g. for additional Desktop Virtualization User role assignments."
  value       = module.desktop_application_group.id
}

output "session_host_names" {
  description = "The names of the session hosts."
  value       = module.session_host[*].name
}

output "session_host_private_ip_addresses" {
  description = "The private IP addresses of the session hosts. Manage through Azure Bastion in the hub; users connect through the AVD clients."
  value       = module.session_host[*].private_ip_address
}

output "session_host_admin_passwords" {
  description = "The generated break-glass local admin passwords, keyed by session host name."
  value       = { for i in range(var.session_host_count) : module.session_host[i].name => random_password.session_host_admin[i].result }
  sensitive   = true
}

output "fslogix_storage_account_name" {
  description = "The name of the FSLogix profile storage account, if deployed."
  value       = var.enable_fslogix ? module.fslogix_storage[0].name : null
}

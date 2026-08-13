output "resource_group_name" {
  description = "The name of the application resource group."
  value       = azurerm_resource_group.this.name
}

output "storage_account_name" {
  description = "The name of the storage account holding the file share."
  value       = module.storage_account.name
}

output "storage_account_id" {
  description = "The ID of the storage account, e.g. to scope further share-level role assignments to."
  value       = module.storage_account.id
}

output "file_share_name" {
  description = "The name of the SMB file share the application's files are saved on."
  value       = var.file_share_name
}

output "file_share_unc_path" {
  description = "The UNC path of the file share. Resolves to the private endpoint from inside the network, so machines in other stacks mount the same path."
  value       = "\\\\${local.file_endpoint_host}\\${var.file_share_name}"
}

output "file_share_drive" {
  description = "The drive the share is mapped to on each machine, e.g. F:."
  value       = "${var.file_share_drive_letter}:"
}

output "virtual_machine_names" {
  description = "The names of the virtual machines the share is mounted on."
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

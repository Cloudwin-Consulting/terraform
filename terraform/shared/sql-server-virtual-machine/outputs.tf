output "id" {
  description = "The ID of the virtual machine."
  value       = module.virtual_machine.id
}

output "name" {
  description = "The name of the virtual machine."
  value       = module.virtual_machine.name
}

output "sql_virtual_machine_id" {
  description = "The ID of the SQL virtual machine registration, e.g. to add the machine to an availability group listener."
  value       = azurerm_mssql_virtual_machine.this.id
}

output "private_ip_address" {
  description = "The private IP address of the virtual machine. Clients reach the instance here, on sql_connectivity_port."
  value       = module.virtual_machine.private_ip_address
}

output "principal_id" {
  description = "The principal ID of the virtual machine's system-assigned managed identity, e.g. to grant it access to a key vault or storage account."
  value       = module.virtual_machine.principal_id
}

output "network_interface_id" {
  description = "The ID of the virtual machine's network interface, e.g. for load balancer backend pool associations."
  value       = module.virtual_machine.network_interface_id
}

output "data_disk_luns_by_role" {
  description = "The LUNs backing each storage role, as handed to the SQL IaaS Agent extension. Useful when extending the machine's storage later, because new disks must not reuse a LUN."
  value       = local.luns_by_role
}

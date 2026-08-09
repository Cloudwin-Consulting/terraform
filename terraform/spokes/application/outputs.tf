output "resource_group_name" {
  description = "The name of the application spoke's core resource group, holding the platform services."
  value       = azurerm_resource_group.this.name
}

output "network_resource_group_name" {
  description = "The name of the application spoke's network resource group, holding the virtual network, its network and application security groups and the NAT gateway."
  value       = azurerm_resource_group.network.name
}

output "dns_resource_group_name" {
  description = "The name of the application spoke's DNS resource group, holding the private DNS zones the spoke owns."
  value       = azurerm_resource_group.dns.name
}

output "secrets_resource_group_name" {
  description = "The name of the application spoke's secrets resource group, holding the platform key vault, if deployed."
  value       = var.enable_platform_key_vault ? azurerm_resource_group.secrets[0].name : null
}

output "virtual_network_id" {
  description = "The ID of the application spoke virtual network, if deployed."
  value       = var.enable_virtual_network ? module.vnet[0].id : null
}

output "virtual_network_name" {
  description = "The name of the application spoke virtual network, if deployed."
  value       = var.enable_virtual_network ? module.vnet[0].name : null
}

output "subnet_ids" {
  description = "Map of application spoke subnet name to subnet ID."
  value       = local.subnet_ids
}

output "api_management_gateway_url" {
  description = "The gateway URL of the API Management instance, if deployed. Resolves to a private address."
  value       = var.enable_virtual_network && var.enable_api_management ? module.api_management[0].gateway_url : null
}

output "api_management_private_ip_addresses" {
  description = "The private IP addresses of the API Management instance, if deployed."
  value       = var.enable_virtual_network && var.enable_api_management ? module.api_management[0].private_ip_addresses : null
}

output "front_door_profile_id" {
  description = "The ID of the Front Door profile, if deployed."
  value       = var.enable_front_door ? module.front_door[0].id : null
}

output "front_door_profile_name" {
  description = "The name of the Front Door profile, if deployed. Applications reference this to add endpoints."
  value       = var.enable_front_door ? module.front_door[0].name : null
}

output "application_gateway_private_ip_address" {
  description = "The private IP address of the application gateway's internal listener - the address the hub firewall's inbound DNAT rule translates to. Populated whether or not the gateway is deployed, because the hub deploys first and has to name this address by hand."
  value       = var.enable_virtual_network ? try(module.application_gateway[0].private_ip_address, local.application_gateway_private_ip_address) : null
}

output "platform_key_vault_name" {
  description = "The name of the spoke's platform key vault, if deployed. Pre-load secrets for application deployments here."
  value       = var.enable_platform_key_vault ? module.platform_key_vault[0].name : null
}

output "platform_key_vault_uri" {
  description = "The URI of the spoke's platform key vault, if deployed. Use it in key vault references."
  value       = var.enable_platform_key_vault ? module.platform_key_vault[0].vault_uri : null
}

output "aks_nsg_name" {
  description = "The name of the network security group on the AKS subnet, if the network is deployed."
  value       = var.enable_virtual_network ? module.nsg_aks[0].name : null
}

output "aks_pod_cidr" {
  description = "The overlay pod range the AKS subnet NSG allows cluster-internal traffic for. The aks stack must deploy its cluster with exactly this pod CIDR."
  value       = var.aks_pod_cidr
}

output "aks_ingress_ip_address" {
  description = "The address reserved for the AKS cluster's internal load balancer frontend. The aks stack must set store_front_load_balancer_ip to exactly this value, or nothing in this spoke can reach the cluster by address."
  value       = var.aks_ingress_ip_address
}

output "private_link_service_subnet_name" {
  description = "The name of the subnet a private link service draws its NAT addresses from, if the network is deployed."
  value       = var.enable_virtual_network ? var.private_link_service_subnet_name : null
}

output "linux_virtual_machine_asg_name" {
  description = "The name of the application security group Linux VM workloads join, if the network is deployed."
  value       = var.enable_virtual_network ? module.asg_linux_virtual_machines[0].name : null
}

output "windows_virtual_machine_asg_name" {
  description = "The name of the application security group Windows VM workloads join, if the network is deployed."
  value       = var.enable_virtual_network ? module.asg_windows_virtual_machines[0].name : null
}

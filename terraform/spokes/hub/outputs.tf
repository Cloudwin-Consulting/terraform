output "resource_group_name" {
  description = "The name of the hub's core resource group, holding the platform services."
  value       = azurerm_resource_group.this.name
}

output "network_resource_group_name" {
  description = "The name of the hub's network resource group, holding the virtual network, network security groups, Bastion, firewall and VPN gateway."
  value       = azurerm_resource_group.network.name
}

output "dns_resource_group_name" {
  description = "The name of the hub's DNS resource group, holding the private DNS zones, their virtual network links and the DNS private resolver."
  value       = azurerm_resource_group.dns.name
}

output "secrets_resource_group_name" {
  description = "The name of the hub's secrets resource group, holding the platform key vault, if deployed."
  value       = var.enable_platform_key_vault ? azurerm_resource_group.secrets[0].name : null
}

output "virtual_network_id" {
  description = "The ID of the hub virtual network, if deployed."
  value       = local.vnet_id
}

output "virtual_network_name" {
  description = "The name of the hub virtual network, if deployed."
  value       = var.enable_virtual_network ? module.vnet[0].name : null
}

output "subnet_ids" {
  description = "Map of hub subnet name to subnet ID."
  value       = local.subnet_ids
}

output "private_dns_zone_ids" {
  description = "Map of private DNS zone name to zone ID."
  value       = { for name, zone in azurerm_private_dns_zone.this : name => zone.id }
}

output "firewall_private_ip_address" {
  description = "The private IP address of the firewall, if deployed. Use as the next hop in spoke route tables."
  value       = var.enable_virtual_network && var.enable_firewall ? module.firewall[0].private_ip_address : null
}

output "firewall_policy_id" {
  description = "The ID of the firewall policy, if deployed. Attach rule collection groups to this."
  value       = var.enable_virtual_network && var.enable_firewall ? module.firewall[0].policy_id : null
}

output "dns_resolver_inbound_ip_address" {
  description = "The IP address of the DNS resolver inbound endpoint, if deployed. Point external DNS forwarders at this address."
  value       = var.enable_virtual_network && var.enable_dns_resolver ? module.dns_resolver[0].inbound_endpoint_ip_address : null
}

output "vpn_gateway_public_ip_address" {
  description = "The public IP address of the VPN gateway, if deployed."
  value       = var.enable_virtual_network && var.enable_vpn_gateway ? module.vpn_gateway[0].public_ip_address : null
}

output "monitor_action_group_id" {
  description = "The ID of the Azure Monitor action group, if deployed. Use it in additional alert rules."
  value       = var.enable_monitor_alerts ? module.monitor[0].action_group_id : null
}

output "platform_key_vault_name" {
  description = "The name of the hub's platform key vault, if deployed. Pre-load secrets for platform deployments here."
  value       = var.enable_platform_key_vault ? module.platform_key_vault[0].name : null
}

output "platform_key_vault_uri" {
  description = "The URI of the hub's platform key vault, if deployed. Use it in key vault references."
  value       = var.enable_platform_key_vault ? module.platform_key_vault[0].vault_uri : null
}

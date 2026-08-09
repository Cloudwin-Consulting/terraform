output "resource_group_name" {
  description = "The name of the application resource group."
  value       = azurerm_resource_group.this.name
}

output "aks_cluster_name" {
  description = "The name of the AKS cluster."
  value       = module.aks.name
}

output "aks_node_resource_group_name" {
  description = "The name of the platform-managed resource group that holds the cluster's infrastructure."
  value       = module.aks.node_resource_group_name
}

output "api_server_fqdn" {
  description = "The fully qualified domain name of the cluster's public API server. Null on a private cluster."
  value       = module.aks.fqdn
}

output "api_server_private_fqdn" {
  description = "The fully qualified domain name of a private cluster's API server, resolvable from networks linked to its private DNS zone. Null on a public cluster."
  value       = module.aks.private_fqdn
}

output "oidc_issuer_url" {
  description = "The URL of the cluster's OIDC issuer, used to federate Kubernetes service accounts with user-assigned identities."
  value       = module.aks.oidc_issuer_url
}

output "container_registry_login_server" {
  description = "The login server of the container registry."
  value       = module.container_registry.login_server
}

output "aks_node_subnet_cidr" {
  description = "The address prefixes of the spoke subnet the cluster's nodes and internal load balancer frontends join."
  value       = data.azurerm_subnet.aks.address_prefixes
}

output "aks_pod_cidr" {
  description = "The overlay range pods draw their addresses from. The spoke's AKS subnet NSG must allow cluster-internal traffic for exactly this range (its aks_pod_cidr input)."
  value       = var.pod_cidr
}

output "aks_service_cidr" {
  description = "The address range Kubernetes services draw their cluster IPs from."
  value       = var.service_cidr
}

output "aks_dns_service_ip" {
  description = "The cluster DNS service's address, within the service CIDR."
  value       = var.dns_service_ip
}

output "store_front_ip_address" {
  description = "The private address of the store front's internal load balancer frontend, in the spoke's AKS subnet. Equals store_front_load_balancer_ip when that is set."
  value       = try(kubernetes_service.store_front.status[0].load_balancer[0].ingress[0].ip, null)
}

output "store_front_private_link_service_id" {
  description = "The ID of the private link service publishing the store front's load balancer, if deployed. Consumers in this tenant connect a private endpoint to it."
  value       = var.enable_private_link_service ? module.store_front_private_link_service[0].id : null
}

output "store_front_private_link_service_alias" {
  description = "The globally unique alias of that private link service, if deployed. Consumers that only hold the alias connect with it instead of the ID."
  value       = var.enable_private_link_service ? module.store_front_private_link_service[0].alias : null
}

output "front_door_endpoint_host_name" {
  description = "The default hostname of the store front's Front Door endpoint, if deployed. Serves 503 until the pending connection on the private link service is approved."
  value       = var.enable_front_door_endpoint ? module.front_door_endpoint[0].host_name : null
}

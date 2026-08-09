output "id" {
  description = "The ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "name" {
  description = "The name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "fqdn" {
  description = "The fully qualified domain name of a public API server. Null on private clusters."
  value       = azurerm_kubernetes_cluster.this.fqdn
}

output "private_fqdn" {
  description = "The fully qualified domain name of a private API server, resolvable from networks linked to its private DNS zone."
  value       = azurerm_kubernetes_cluster.this.private_fqdn
}

output "node_resource_group_name" {
  description = "The name of the platform-managed resource group that holds the cluster's infrastructure."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "kubelet_identity_object_id" {
  description = "The object ID of the kubelet's managed identity. Grant it AcrPull on the container registries the cluster pulls images from."
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "oidc_issuer_url" {
  description = "The URL of the cluster's OIDC issuer, used to federate Kubernetes service accounts with user-assigned identities."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "key_vault_secrets_provider_identity_object_id" {
  description = "The object ID of the key vault secrets provider's identity, granted access to the vaults it mounts secrets from. Null when the provider is disabled."
  value       = try(azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0].object_id, null)
}

# Cluster credentials for the Kubernetes and Helm providers: the
# administrator credentials on Microsoft Entra ID integrated clusters,
# otherwise the cluster's certificate credentials. Empty when local
# accounts are disabled - deployments then authenticate with Entra ID
# tokens instead.

output "host" {
  description = "The API server endpoint of the cluster's credentials."
  value       = try(local.kube_config.host, null)
  sensitive   = true
}

output "client_certificate" {
  description = "The base64-encoded client certificate of the cluster's credentials."
  value       = try(local.kube_config.client_certificate, null)
  sensitive   = true
}

output "client_key" {
  description = "The base64-encoded client key of the cluster's credentials."
  value       = try(local.kube_config.client_key, null)
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "The base64-encoded certificate authority certificate of the cluster."
  value       = try(local.kube_config.cluster_ca_certificate, null)
  sensitive   = true
}

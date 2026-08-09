output "id" {
  description = "The ID of the AI Services account."
  value       = azurerm_cognitive_account.this.id
}

output "name" {
  description = "The name of the AI Services account."
  value       = azurerm_cognitive_account.this.name
}

output "endpoint" {
  description = "The endpoint callers send requests to. Resolves to the private endpoint from inside the network."
  value       = azurerm_cognitive_account.this.endpoint
}

output "custom_subdomain_name" {
  description = "The custom subdomain the endpoint is built from."
  value       = azurerm_cognitive_account.this.custom_subdomain_name
}

output "principal_id" {
  description = "The principal ID of the account's system-assigned managed identity, e.g. for granting it access to a storage account holding fine-tuning or grounding data."
  value       = azurerm_cognitive_account.this.identity[0].principal_id
}

output "model_deployment_names" {
  description = "The names of the model deployments - the deployment names callers pass in their requests."
  value       = [for name, deployment in azurerm_cognitive_deployment.this : deployment.name]
}

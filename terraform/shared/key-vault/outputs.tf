output "id" {
  description = "The ID of the key vault."
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "The name of the key vault."
  value       = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = "The URI of the key vault data plane. Resolves to the private endpoint from inside the network."
  value       = azurerm_key_vault.this.vault_uri
}

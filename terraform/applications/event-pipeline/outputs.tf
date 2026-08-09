output "event_hub_namespace_fqdn" {
  description = "The fully qualified namespace producers send telemetry to with their managed identities."
  value       = "${module.event_hub.name}.servicebus.windows.net"
}

output "cosmos_endpoint" {
  description = "The endpoint of the Cosmos DB account holding the materialised view."
  value       = module.cosmos.endpoint
}

output "function_app_name" {
  description = "The name of the consumer function app."
  value       = module.function_app.function_app_name
}

output "key_vault_name" {
  description = "The name of the pipeline's key vault. Pre-load application secrets here through the Secrets Officer flow."
  value       = module.key_vault.name
}

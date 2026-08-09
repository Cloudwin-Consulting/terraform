output "api_default_hostname" {
  description = "The default hostname of the API, resolved to its private endpoint from inside the network."
  value       = module.app_service.default_hostname
}

output "postgresql_fqdn" {
  description = "The fully qualified domain name of the PostgreSQL server, resolved through the hub's postgres private DNS zone."
  value       = module.postgresql.fqdn
}

output "redis_hostname" {
  description = "The hostname of the Redis cache, resolved to its private endpoint from inside the network."
  value       = module.redis.hostname
}

output "app_configuration_endpoint" {
  description = "The endpoint of the App Configuration store."
  value       = module.app_configuration.endpoint
}

output "key_vault_name" {
  description = "The name of the API's key vault. Pre-load application secrets here through the Secrets Officer flow."
  value       = module.key_vault.name
}

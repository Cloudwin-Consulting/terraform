output "id" {
  description = "The ID of the Redis cache."
  value       = azurerm_redis_cache.this.id
}

output "name" {
  description = "The name of the Redis cache."
  value       = azurerm_redis_cache.this.name
}

output "hostname" {
  description = "The hostname of the Redis cache. Resolves to the private endpoint from inside the network."
  value       = azurerm_redis_cache.this.hostname
}

output "ssl_port" {
  description = "The TLS port of the Redis cache."
  value       = azurerm_redis_cache.this.ssl_port
}

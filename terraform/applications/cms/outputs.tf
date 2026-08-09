output "cms_default_hostname" {
  description = "The default hostname of the CMS, resolved to its private endpoint from inside the network."
  value       = module.app_service.default_hostname
}

output "mysql_fqdn" {
  description = "The fully qualified domain name of the MySQL server, resolved through the hub's mysql private DNS zone."
  value       = module.mysql.fqdn
}

output "media_storage_account_name" {
  description = "The name of the media storage account."
  value       = module.media_storage.name
}

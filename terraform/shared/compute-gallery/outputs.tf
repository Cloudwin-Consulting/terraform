output "id" {
  description = "The ID of the compute gallery."
  value       = azurerm_shared_image_gallery.this.id
}

output "name" {
  description = "The name of the compute gallery."
  value       = azurerm_shared_image_gallery.this.name
}

output "image_ids" {
  description = "Map of image definition name to image definition ID. In source_image_id, append /versions/<version> to pin a published version, or pass the definition ID unchanged to deploy its latest version - either way at least one version must have been published."
  value       = { for name, image in azurerm_shared_image.this : name => image.id }
}

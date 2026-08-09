output "gallery_id" {
  description = "The ID of the compute gallery."
  value       = module.compute_gallery.id
}

output "image_ids" {
  description = "The IDs of the gallery image definitions, keyed by image name. Point a VM stack's source_image_id at one of these (or a specific version under it) to boot from the golden image."
  value       = module.compute_gallery.image_ids
}

output "builder_private_ip_address" {
  description = "The private IP address of the builder machine, reached through Azure Bastion."
  value       = module.builder.private_ip_address
}

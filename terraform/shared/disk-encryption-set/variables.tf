variable "name" {
  description = "The name of the disk encryption set."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the disk encryption set is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the disk encryption set is deployed."
  type        = string
}

variable "key_vault_id" {
  description = "The ID of the key vault holding the key, used to grant the set's identity access."
  type        = string
}

variable "key_vault_key_id" {
  description = "The ID of the customer-managed key, pre-created by administrators from inside the network. Use a versionless ID with automatic rotation."
  type        = string
}

variable "auto_key_rotation_enabled" {
  description = "Whether disks re-encrypt automatically when the key rotates to a new version."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the disk encryption set."
  type        = map(string)
  default     = {}
}

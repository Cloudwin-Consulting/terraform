variable "name" {
  description = "The name of the workspace."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the workspace is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the workspace is deployed."
  type        = string
}

variable "friendly_name" {
  description = "The friendly name of the workspace, shown in the AVD clients."
  type        = string
  default     = null
}

variable "description" {
  description = "A description of the workspace."
  type        = string
  default     = null
}

variable "application_group_ids" {
  description = "IDs of the application groups the workspace publishes, keyed by a static label naming each association, e.g. { desktop = module.desktop_application_group.id }. The labels must be known at plan time; the IDs may come from groups deployed in the same apply."
  type        = map(string)
  default     = {}
}

variable "public_network_access_enabled" {
  description = "Whether clients fetch the workspace's feed over its public endpoint. Disabling it requires AVD Private Link private endpoints (the private-endpoint module with the feed subresource, plus one per-tenant global endpoint) before the feed keeps resolving."
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace the AVD workspace's logs are sent to. Leave null to skip diagnostics."
  type        = string
  default     = null
}

variable "enable_diagnostics" {
  description = "Whether to create the diagnostic setting. Defaults to whether log_analytics_workspace_id is set; set explicitly when the workspace ID comes from a resource created in the same apply, because an unknown ID cannot decide the count."
  type        = bool
  default     = null
}

variable "tags" {
  description = "Tags applied to the workspace."
  type        = map(string)
  default     = {}
}

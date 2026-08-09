variable "name" {
  description = "The name of the Log Analytics workspace."
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

variable "sku" {
  description = "The SKU of the workspace."
  type        = string
  default     = "PerGB2018"
}

variable "retention_in_days" {
  description = "The number of days data is retained in the workspace."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "retention_in_days must be between 30 and 730."
  }
}

variable "daily_quota_gb" {
  description = "The daily ingestion cap in GB. Leave null for no cap."
  type        = number
  default     = null
}

variable "internet_ingestion_enabled" {
  description = "Whether the workspace accepts ingestion over the public internet. Keep disabled and ingest through an Azure Monitor Private Link Scope."
  type        = bool
  default     = false
}

variable "internet_query_enabled" {
  description = "Whether the workspace can be queried over the public internet."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the workspace."
  type        = map(string)
  default     = {}
}

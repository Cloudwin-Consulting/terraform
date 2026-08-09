variable "name" {
  description = "The name of the Application Insights component."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the component is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the component is deployed."
  type        = string
}

variable "application_type" {
  description = "The type of application being monitored, e.g. web."
  type        = string
  default     = "web"

  validation {
    condition     = contains(["web", "other", "java", "ios", "phone", "store", "MobileCenter", "Node.JS"], var.application_type)
    error_message = "application_type must be a valid Application Insights type, e.g. web."
  }
}

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace that stores the component's telemetry."
  type        = string
}

variable "retention_in_days" {
  description = "The number of days telemetry is retained in the component."
  type        = number
  default     = 90

  validation {
    condition     = contains([30, 60, 90, 120, 180, 270, 365, 550, 730], var.retention_in_days)
    error_message = "retention_in_days must be one of 30, 60, 90, 120, 180, 270, 365, 550 or 730."
  }
}

variable "local_authentication_disabled" {
  description = "Whether ingestion with the instrumentation key alone is disabled. Keep disabled and authenticate telemetry with Microsoft Entra ID."
  type        = bool
  default     = true
}

variable "internet_ingestion_enabled" {
  description = "Whether the component accepts telemetry over the public internet. Keep disabled and ingest through an Azure Monitor Private Link Scope."
  type        = bool
  default     = false
}

variable "internet_query_enabled" {
  description = "Whether the component can be queried over the public internet."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the component."
  type        = map(string)
  default     = {}
}

variable "name" {
  description = "The name of the API Management instance. Must be globally unique as it forms the default hostnames."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the instance is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the instance is deployed."
  type        = string
}

variable "publisher_name" {
  description = "The name of the API publisher organisation."
  type        = string
}

variable "publisher_email" {
  description = "The email address of the API publisher."
  type        = string

  validation {
    condition     = can(regex("^.+@.+$", var.publisher_email))
    error_message = "publisher_email must be an email address."
  }
}

variable "sku_name" {
  description = "The SKU of the instance including capacity. Only Developer and Premium support virtual network injection."
  type        = string
  default     = "Developer_1"

  validation {
    condition     = can(regex("^(Developer_1|Premium_[1-9][0-9]?)$", var.sku_name))
    error_message = "sku_name must be Developer_1 (the Developer tier is fixed at one unit) or Premium_N with at least one unit; only those tiers support virtual network injection."
  }
}

variable "subnet_id" {
  description = "The ID of the subnet the instance joins in internal virtual network mode."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "The ID of a Log Analytics workspace to send diagnostics to. Leave null to skip diagnostics."
  type        = string
  default     = null
}

variable "enable_diagnostics" {
  description = "Whether to create the diagnostic setting. Defaults to creating it when log_analytics_workspace_id is set. Set explicitly when the workspace is created in the same apply: its ID is unknown at plan time, so it cannot decide whether the setting exists."
  type        = bool
  default     = null

  validation {
    condition     = var.enable_diagnostics != true || var.log_analytics_workspace_id != null
    error_message = "enable_diagnostics requires log_analytics_workspace_id to be set."
  }
}

variable "tags" {
  description = "Tags applied to the instance."
  type        = map(string)
  default     = {}
}

variable "zones" {
  description = "Availability zones of the deployment, e.g. [\"1\", \"2\", \"3\"] for zone redundancy. Requires a Premium SKU with at least as many units as zones. Leave null for a regional deployment."
  type        = list(string)
  default     = null

  validation {
    condition = (
      var.zones == null ||
      can(regex("^Premium_", var.sku_name)) && tonumber(try(regex("[0-9]+$", var.sku_name), "0")) >= length(coalesce(var.zones, []))
    )
    error_message = "zones requires a Premium SKU with at least as many units as zones, e.g. Premium_3 for three zones."
  }
}

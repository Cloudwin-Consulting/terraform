variable "virtual_machine_id" {
  description = "The ID of the virtual machine the agent is installed on. The machine needs a system-assigned managed identity."
  type        = string
}

variable "os_type" {
  description = "The operating system of the virtual machine, Linux or Windows."
  type        = string

  validation {
    condition     = contains(["Linux", "Windows"], var.os_type)
    error_message = "os_type must be Linux or Windows."
  }
}

variable "data_collection_rule_id" {
  description = "The ID of an existing data collection rule to associate. Leave null to create a default rule from log_analytics_workspace_id."
  type        = string
  default     = null

  validation {
    condition     = var.data_collection_rule_id != null || var.log_analytics_workspace_id != null
    error_message = "The agent needs a telemetry destination: set data_collection_rule_id or log_analytics_workspace_id."
  }
}

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace the default data collection rule sends to. Ignored when data_collection_rule_id is set."
  type        = string
  default     = null

  validation {
    condition     = var.log_analytics_workspace_id == null || (var.resource_group_name != null && var.location != null)
    error_message = "resource_group_name and location are required when the module creates the default data collection rule."
  }
}

variable "data_collection_endpoint_id" {
  description = "The ID of a data collection endpoint the agent fetches its rule configuration through. Required when the workspace only ingests over private link, so the agent can reach configuration and ingestion privately."
  type        = string
  default     = null
}

variable "create_data_collection_rule" {
  description = "Whether to create the default data collection rule. Defaults to creating it when log_analytics_workspace_id is set and data_collection_rule_id is not. Set explicitly when the workspace is created in the same apply: its ID is unknown at plan time, so it cannot decide whether the rule exists."
  type        = bool
  default     = null

  validation {
    condition     = var.create_data_collection_rule != true || (var.data_collection_rule_id == null && var.log_analytics_workspace_id != null)
    error_message = "create_data_collection_rule requires log_analytics_workspace_id and no data_collection_rule_id."
  }
}

variable "associate_data_collection_endpoint" {
  description = "Whether to create the configuration-access association to the data collection endpoint. Defaults to creating it when data_collection_endpoint_id is set. Set explicitly when the endpoint is created in the same apply: its ID is unknown at plan time, so it cannot decide whether the association exists."
  type        = bool
  default     = null

  validation {
    condition     = var.associate_data_collection_endpoint != true || var.data_collection_endpoint_id != null
    error_message = "associate_data_collection_endpoint requires data_collection_endpoint_id to be set."
  }
}

variable "data_collection_rule_name" {
  description = "The name of the default data collection rule, when one is created."
  type        = string
  default     = "dcr-monitor-agent"
}

variable "resource_group_name" {
  description = "The resource group the default data collection rule is created in. Required when the default rule is created."
  type        = string
  default     = null
}

variable "location" {
  description = "The Azure location of the default data collection rule. Required when the default rule is created."
  type        = string
  default     = null
}

variable "type_handler_version" {
  description = "The base version of the agent extension. Minor versions upgrade automatically."
  type        = string
  default     = "1.0"
}

variable "tags" {
  description = "Tags applied to the agent resources."
  type        = map(string)
  default     = {}
}

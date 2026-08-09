variable "name" {
  description = "The name of the data factory. Must be globally unique."
  type        = string

  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 63 && can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$", var.name))
    error_message = "The data factory name must be 3-63 characters of letters, numbers and hyphens, starting and ending alphanumeric."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the data factory is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the data factory is deployed."
  type        = string
}

variable "public_network_enabled" {
  description = "Whether the factory's endpoint is reachable over the public internet. Keep disabled and reach the authoring and monitoring endpoints through a private endpoint (the dataFactory subresource, resolved by privatelink.datafactory.azure.net)."
  type        = bool
  default     = false
}

variable "managed_virtual_network_enabled" {
  description = "Whether integration runtimes run inside the factory's managed virtual network, reaching data stores through managed private endpoints rather than the public internet. Keep enabled: turning it off puts every activity's egress back on public endpoints."
  type        = bool
  default     = true
}

variable "user_assigned_identity_ids" {
  description = "User-assigned identity IDs attached to the factory alongside its system-assigned identity, e.g. an identity the data stores already trust. Leave empty for the system-assigned identity alone."
  type        = list(string)
  default     = []
}

variable "customer_managed_key" {
  description = "Encrypts the factory's stored definitions with a customer-managed key. identity_id must be one of user_assigned_identity_ids, granted wrap and unwrap on a purge-protected vault. Leave null for platform-managed keys."
  type = object({
    key_vault_key_id = string
    identity_id      = string
  })
  default = null

  validation {
    condition     = var.customer_managed_key == null || contains(var.user_assigned_identity_ids, try(var.customer_managed_key.identity_id, ""))
    error_message = "customer_managed_key.identity_id must be one of user_assigned_identity_ids: the factory unwraps the key with an identity it has attached, not with its system-assigned identity and not with one it never joined."
  }
}

variable "purview_id" {
  description = "The ID of a Microsoft Purview account the factory reports lineage to. Leave null to skip the connection."
  type        = string
  default     = null
}

variable "github_configuration" {
  description = "Authors pipelines against a GitHub repository instead of the live factory. Mutually exclusive with vsts_configuration; leave both null to author against the factory itself."
  type = object({
    account_name       = string
    branch_name        = string
    repository_name    = string
    root_folder        = optional(string, "/")
    git_url            = optional(string, "https://github.com")
    publishing_enabled = optional(bool, true)
  })
  default = null
}

variable "vsts_configuration" {
  description = "Authors pipelines against an Azure DevOps repository instead of the live factory. Mutually exclusive with github_configuration; leave both null to author against the factory itself."
  type = object({
    account_name       = string
    branch_name        = string
    project_name       = string
    repository_name    = string
    tenant_id          = string
    root_folder        = optional(string, "/")
    publishing_enabled = optional(bool, true)
  })
  default = null

  validation {
    condition     = var.vsts_configuration == null || var.github_configuration == null
    error_message = "A factory authors against one repository: set github_configuration or vsts_configuration, not both."
  }
}

variable "global_parameters" {
  description = "Global parameters available to every pipeline, keyed by parameter name. Never put a secret here - the values are stored in the factory and in Terraform state; keep secrets in a key vault linked service instead."
  type = map(object({
    type  = string
    value = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, parameter in var.global_parameters :
      contains(["Array", "Bool", "Float", "Int", "Object", "String"], parameter.type)
    ])
    error_message = "A global parameter's type must be Array, Bool, Float, Int, Object or String."
  }
}

variable "azure_integration_runtimes" {
  description = "Azure integration runtimes activities run on, keyed by runtime name. location defaults to the factory's region; set it to AutoResolve to let the service pick the region closest to the sink. time_to_live_min keeps the cluster warm between activities, trading cost for start-up latency. Each runtime joins the managed virtual network when managed_virtual_network_enabled is true."
  type = map(object({
    description      = optional(string)
    location         = optional(string)
    compute_type     = optional(string, "General")
    core_count       = optional(number, 8)
    time_to_live_min = optional(number, 0)
    cleanup_enabled  = optional(bool, true)
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, runtime in var.azure_integration_runtimes :
      contains(["General", "ComputeOptimized", "MemoryOptimized"], runtime.compute_type)
    ])
    error_message = "compute_type must be General, ComputeOptimized or MemoryOptimized."
  }

  validation {
    condition = alltrue([
      for name, runtime in var.azure_integration_runtimes :
      contains([8, 16, 32, 48, 80, 144, 272], runtime.core_count)
    ])
    error_message = "core_count must be one of 8, 16, 32, 48, 80, 144 or 272."
  }

  # No upper bound: the provider imposes none, and the ceiling varies by
  # cluster type, so an invented limit here would reject configurations
  # the service accepts.
  validation {
    condition = alltrue([
      for name, runtime in var.azure_integration_runtimes :
      runtime.time_to_live_min >= 0 && floor(runtime.time_to_live_min) == runtime.time_to_live_min
    ])
    error_message = "time_to_live_min must be a whole, non-negative number of minutes. Zero keeps no cluster warm between activities; a longer time trades cost for start-up latency."
  }

  # Terraform's map keys are distinct case-sensitively; Azure Resource
  # Manager compares names case-insensitively. Both entries plan, and
  # the second to apply collides with the first.
  validation {
    condition     = length(distinct([for name, runtime in var.azure_integration_runtimes : lower(name)])) == length(var.azure_integration_runtimes)
    error_message = "Integration runtime names must be unique within the factory, ignoring case: Azure Resource Manager compares resource names case-insensitively, so two keys differing only in capitalisation name the same runtime."
  }
}

variable "managed_private_endpoints" {
  description = "Managed private endpoints from the factory's managed virtual network to the data stores it reads and writes, keyed by endpoint name. subresource_name is the target's subresource, e.g. blob for a storage account or sqlServer for a SQL server. Each connection arrives at its target pending approval - approve it after the first deployment."
  type = map(object({
    target_resource_id = string
    subresource_name   = optional(string)
    fqdns              = optional(list(string))
  }))
  default = {}

  validation {
    condition     = length(var.managed_private_endpoints) == 0 || var.managed_virtual_network_enabled
    error_message = "managed_private_endpoints require managed_virtual_network_enabled: they are created inside the factory's managed virtual network."
  }

  validation {
    condition     = length(distinct([for name, endpoint in var.managed_private_endpoints : lower(name)])) == length(var.managed_private_endpoints)
    error_message = "Managed private endpoint names must be unique within the factory, ignoring case: Azure Resource Manager compares resource names case-insensitively, so two keys differing only in capitalisation name the same endpoint."
  }
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
  description = "Tags applied to the data factory."
  type        = map(string)
  default     = {}
}

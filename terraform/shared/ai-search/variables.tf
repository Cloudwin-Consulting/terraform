variable "name" {
  description = "The name of the search service. Must be globally unique as it forms the endpoint hostname, https://<name>.search.windows.net."
  type        = string

  validation {
    condition     = length(var.name) >= 2 && length(var.name) <= 60 && can(regex("^[a-z0-9]{2}([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "The search service name must be 2-60 characters of lower-case letters, numbers and hyphens, with the first two and the last character alphanumeric - a hyphen may not sit in any of those three positions."
  }

  validation {
    condition     = !can(regex("--", var.name))
    error_message = "The search service name cannot contain consecutive hyphens."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the search service is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the search service is deployed."
  type        = string
}

variable "sku" {
  description = "The SKU of the service: free, basic, standard, standard2, standard3, storage_optimized_l1 or storage_optimized_l2. Fixed at creation - changing it replaces the service. The free SKU has no private endpoint, no managed identity and no SLA."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["free", "basic", "standard", "standard2", "standard3", "storage_optimized_l1", "storage_optimized_l2"], var.sku)
    error_message = "sku must be free, basic, standard, standard2, standard3, storage_optimized_l1 or storage_optimized_l2."
  }
}

variable "replica_count" {
  description = "The number of replicas, each serving queries. Two or more give a read SLA, three or more a read-write SLA. The ceiling is the SKU's: 1 on free, 3 on basic and 12 from standard upwards."
  type        = number
  default     = 1

  validation {
    condition     = var.replica_count >= 1 && var.replica_count <= 12 && floor(var.replica_count) == var.replica_count
    error_message = "replica_count must be a whole number between 1 and 12: a replica is a discrete instance serving queries."
  }

  validation {
    condition     = var.replica_count <= (var.sku == "free" ? 1 : var.sku == "basic" ? 3 : 12)
    error_message = "replica_count exceeds the SKU's limit: a free service supports 1 replica, a basic service 3, and standard and above 12."
  }
}

variable "partition_count" {
  description = "The number of partitions the indexes are spread across, each adding index storage. The free SKU is fixed at one; basic takes up to three, on services created after 3 April 2024 in a region where the higher capacity is enabled - an older basic service stays at one until it is upgraded; standard and above take 1, 2, 3, 4, 6 or 12."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 2, 3, 4, 6, 12], var.partition_count)
    error_message = "partition_count must be 1, 2, 3, 4, 6 or 12."
  }

  validation {
    condition     = var.partition_count == 1 || var.sku != "free"
    error_message = "partition_count must be 1 on the free SKU."
  }

  validation {
    condition     = var.sku != "basic" || var.partition_count <= 3
    error_message = "partition_count must be 3 or fewer on the basic SKU."
  }

  validation {
    condition     = var.hosting_mode != "highDensity" || contains([1, 2, 3], var.partition_count)
    error_message = "highDensity hosting supports 1, 2 or 3 partitions: it trades partition count for the number of indexes a standard3 service can hold."
  }

  # A service is billed and capped in search units, which is replicas
  # multiplied by partitions - so the two limits are not independent of
  # each other however each one reads on its own.
  validation {
    condition = (
      var.sku == "free" ||
      var.replica_count * var.partition_count <= (var.sku == "basic" ? 9 : 36)
    )
    error_message = "replica_count multiplied by partition_count exceeds the service's search unit ceiling: 9 on basic (three replicas and three partitions) and 36 from standard upwards."
  }
}

variable "hosting_mode" {
  description = "How indexes are hosted: default, or highDensity to pack many small indexes onto a standard3 service."
  type        = string
  default     = "default"

  validation {
    condition     = contains(["default", "highDensity"], var.hosting_mode)
    error_message = "hosting_mode must be default or highDensity."
  }

  validation {
    condition     = var.hosting_mode == "default" || var.sku == "standard3"
    error_message = "highDensity hosting requires the standard3 SKU."
  }
}

variable "semantic_search_sku" {
  description = "The semantic ranker tier: free (limited monthly queries) or standard. Leave null to leave semantic ranking off. Ignored on the free SKU."
  type        = string
  default     = null

  validation {
    condition     = var.semantic_search_sku == null || contains(["free", "standard"], coalesce(var.semantic_search_sku, "free"))
    error_message = "semantic_search_sku must be free or standard."
  }
}

variable "local_authentication_enabled" {
  description = "Whether callers may authenticate with the service's admin and query API keys. Keep disabled so Microsoft Entra ID and RBAC are the only path - callers hold Search Index Data Reader or Search Index Data Contributor instead of a key."
  type        = bool
  default     = false
}

variable "authentication_failure_mode" {
  description = "What a failed key authentication returns while local authentication is enabled: http401WithBearerChallenge or http403. Ignored when local_authentication_enabled is false."
  type        = string
  default     = "http401WithBearerChallenge"

  validation {
    condition     = contains(["http401WithBearerChallenge", "http403"], var.authentication_failure_mode)
    error_message = "authentication_failure_mode must be http401WithBearerChallenge or http403."
  }
}

variable "public_network_access_enabled" {
  description = "Whether the service is reachable over the public internet. Keep disabled and query it through a private endpoint (the searchService subresource, resolved by privatelink.search.windows.net). Requires the basic SKU or above."
  type        = bool
  default     = false

  validation {
    condition     = var.public_network_access_enabled || var.sku != "free"
    error_message = "Disabled public network access requires the basic SKU or above: a free search service has no private endpoint, so it would have no usable endpoint at all."
  }
}

variable "allowed_ips" {
  description = "Public addresses or CIDR ranges allowed while the public endpoint is open. Azure AI Search has no default-deny action: an empty rule set is not a deny-all, it is no restriction at all, so an open endpoint with no rules is reachable from every address on the internet. The module therefore requires an allow list whenever the public endpoint is open - pass [\"0.0.0.0/0\"] to open it to everything deliberately. The free SKU is the exception: it supports no IP rules at all, so it takes an empty list and is reachable from anywhere by nature. Ignored when public_network_access_enabled is false."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.public_network_access_enabled || var.sku == "free" || length(var.allowed_ips) > 0
    error_message = "An open public endpoint needs allowed_ips: unlike a storage account's default-deny ACL, an empty Azure AI Search rule set restricts nothing and leaves the service reachable from the whole internet. List the permitted ranges, or pass [\"0.0.0.0/0\"] to open it deliberately."
  }

  validation {
    condition     = length(var.allowed_ips) == 0 || var.sku != "free"
    error_message = "The free SKU supports no IP firewall rules: leave allowed_ips empty on it, and use the basic SKU or above for a service whose public endpoint must be restricted."
  }
}

variable "network_rule_bypass_option" {
  description = "Which trusted Azure services may reach the service past its network rules: None, or AzureServices for the portal's index designer and an AI Services skillset callback. Keep None unless one of those is needed. The service accepts no other value."
  type        = string
  default     = "None"

  validation {
    condition     = contains(["None", "AzureServices"], var.network_rule_bypass_option)
    error_message = "network_rule_bypass_option must be None or AzureServices."
  }
}

variable "customer_managed_key_enforcement_enabled" {
  description = "Whether the service refuses to serve indexes and synonym maps that are not encrypted with a customer-managed key, rather than falling back to platform keys. Requires every index to name a key vault key, and the basic SKU or above - the free tier has no managed identity to unwrap one with."
  type        = bool
  default     = false

  validation {
    condition     = !var.customer_managed_key_enforcement_enabled || var.sku != "free"
    error_message = "customer_managed_key_enforcement_enabled requires the basic SKU or above: a free search service supports neither customer-managed keys nor the managed identity that unwraps them, so enforcement would leave a service on which no index can be created."
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
  description = "Tags applied to the search service."
  type        = map(string)
  default     = {}
}

variable "name" {
  description = "The name of the application gateway."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the application gateway is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the application gateway is deployed."
  type        = string
}

variable "subnet_id" {
  description = "The ID of the dedicated application gateway subnet."
  type        = string
}

variable "private_ip_address" {
  description = "The static private IP address of the internal frontend. Must sit inside the subnet's range."
  type        = string
}

variable "sku_name" {
  description = "The SKU of the application gateway: Standard_v2 or WAF_v2."
  type        = string
  default     = "Standard_v2"

  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.sku_name)
    error_message = "sku_name must be Standard_v2 or WAF_v2."
  }
}

variable "sku_tier" {
  description = "The tier of the application gateway: Standard_v2 or WAF_v2. Must match sku_name."
  type        = string
  default     = "Standard_v2"

  validation {
    condition     = var.sku_tier == var.sku_name && contains(["Standard_v2", "WAF_v2"], var.sku_tier)
    error_message = "sku_tier must match sku_name and be Standard_v2 or WAF_v2."
  }
}

variable "min_capacity" {
  description = "The minimum autoscale capacity."
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "The maximum autoscale capacity."
  type        = number
  default     = 2

  validation {
    condition     = var.max_capacity >= var.min_capacity && var.max_capacity <= 125
    error_message = "max_capacity must be at least min_capacity and at most 125."
  }
}

variable "backend_fqdns" {
  description = "Hostnames of the backend pool members, e.g. web app default hostnames. Mutually exclusive with backend_ip_addresses."
  type        = list(string)
  default     = []
}

variable "backend_ip_addresses" {
  description = "Addresses of the backend pool members, for backends that have no hostname of their own - e.g. a Kubernetes internal load balancer frontend. Mutually exclusive with backend_fqdns."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for address in var.backend_ip_addresses : can(cidrhost("${address}/32", 0))])
    error_message = "Every entry in backend_ip_addresses must be a valid IP address."
  }

  validation {
    condition     = length(var.backend_fqdns) == 0 || length(var.backend_ip_addresses) == 0
    error_message = "The backend pool takes either backend_fqdns or backend_ip_addresses, not both."
  }
}

variable "backend_protocol" {
  description = "The protocol the gateway speaks to the backend: Http or Https. Https suits the App Service backends the default fits; use Http for a backend that terminates no TLS of its own, e.g. a plain-HTTP Kubernetes service."
  type        = string
  default     = "Https"

  validation {
    condition     = contains(["Http", "Https"], var.backend_protocol)
    error_message = "backend_protocol must be Http or Https."
  }
}

variable "backend_port" {
  description = "The port the gateway connects to on the backend."
  type        = number
  default     = 443

  validation {
    condition     = var.backend_port >= 1 && var.backend_port <= 65535
    error_message = "backend_port must be between 1 and 65535."
  }
}

variable "backend_probe_protocol" {
  description = "The protocol the health probe uses. Leave null to follow backend_protocol."
  type        = string
  default     = null

  validation {
    condition     = var.backend_probe_protocol == null || contains(["Http", "Https"], coalesce(var.backend_probe_protocol, "Https"))
    error_message = "backend_probe_protocol must be Http or Https."
  }
}

variable "backend_host_name" {
  description = "The host header the gateway sends to the backend. Leave null to take it from the backend address, which only an FQDN backend carries."
  type        = string
  default     = null
}

variable "backend_probe_path" {
  description = "The path probed to assess backend health."
  type        = string
  default     = "/"
}

variable "ssl_certificate_key_vault_secret_id" {
  description = "The key vault secret ID of the listener's TLS certificate. Requires a user-assigned identity with access to the vault. Leave null for a plain HTTP listener."
  type        = string
  default     = null

  validation {
    condition     = var.ssl_certificate_key_vault_secret_id == null || length(var.identity_ids) > 0
    error_message = "A key vault TLS certificate requires at least one identity in identity_ids: the gateway retrieves the certificate with a user-assigned managed identity."
  }
}

variable "identity_ids" {
  description = "User-assigned identity IDs, required to read a key vault TLS certificate."
  type        = list(string)
  default     = []
}

variable "waf_mode" {
  description = "The firewall mode when the WAF_v2 tier is used: Detection or Prevention."
  type        = string
  default     = "Prevention"

  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "waf_mode must be Detection or Prevention."
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
  description = "Tags applied to the application gateway resources."
  type        = map(string)
  default     = {}
}

variable "zones" {
  description = "Availability zones of the deployment, e.g. [\"1\", \"2\", \"3\"] for zone redundancy. Leave null for a regional deployment."
  type        = list(string)
  default     = null
}

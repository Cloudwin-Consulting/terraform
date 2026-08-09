variable "name" {
  description = "The name of the storage account. Must be globally unique, 3-24 lowercase letters and numbers."
  type        = string

  validation {
    condition = (
      length(var.name) >= 3 &&
      length(var.name) <= 24 &&
      can(regex("^[a-z0-9]+$", var.name))
    )
    error_message = "The storage account name must be between 3 and 24 characters and contain only lowercase letters and numbers."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the storage account is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the storage account is deployed."
  type        = string
}

variable "account_tier" {
  description = "The performance tier of the storage account."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tier must be Standard or Premium."
  }
}

variable "account_replication_type" {
  description = "The replication type of the storage account, e.g. LRS, ZRS, GRS."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS or RAGZRS."
  }
}

variable "access_tier" {
  description = "The default access tier for blob data."
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool", "Cold"], var.access_tier)
    error_message = "access_tier must be Hot, Cool or Cold."
  }
}

variable "shared_access_key_enabled" {
  description = "Whether shared key authorisation is allowed. Keep disabled and grant access with Microsoft Entra ID and RBAC."
  type        = bool
  default     = false
}

variable "sas_expiration_period" {
  description = "The upper bound on the lifetime of shared access signatures, in DD.HH:MM:SS format; SAS tokens asking for a longer lifetime are blocked. Only relevant when shared key authorisation is enabled, since account SAS tokens are signed with the account keys."
  type        = string
  default     = "01.00:00:00"

  validation {
    condition     = can(regex("^\\d{1,4}\\.([01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d$", var.sas_expiration_period))
    error_message = "sas_expiration_period must be in DD.HH:MM:SS format with hours below 24 and minutes and seconds below 60, e.g. 01.00:00:00."
  }
}

variable "customer_managed_key" {
  description = "Encrypts the storage account with a customer-managed key held in a key vault instead of Microsoft-managed keys. Pre-create the key from inside the network in a vault with purge protection enabled; the account's system-assigned identity is granted the Key Vault Crypto Service Encryption User role on the vault to wrap and unwrap it. The vault must keep public network access enabled with default-deny network rules and the trusted-services bypass (the key-vault module's public_network_access_enabled = true): Azure Storage reaches the key as a trusted service through the vault's public endpoint, and the bypass does not apply to a vault whose public endpoint is disabled. Leave key_version null to follow new key versions automatically. Leave the variable null for Microsoft-managed keys."
  type = object({
    key_vault_id = string
    key_name     = string
    key_version  = optional(string)
  })
  default = null
}

variable "public_network_access_enabled" {
  description = "Whether the storage account is reachable over the public internet. Keep disabled and access data through private endpoints."
  type        = bool
  default     = false
}

variable "blob_versioning_enabled" {
  description = "Whether blob versioning is enabled."
  type        = bool
  default     = true
}

variable "blob_soft_delete_retention_days" {
  description = "Days deleted blobs are retained for recovery."
  type        = number
  default     = 7

  validation {
    condition     = var.blob_soft_delete_retention_days >= 1 && var.blob_soft_delete_retention_days <= 365
    error_message = "blob_soft_delete_retention_days must be between 1 and 365."
  }
}

variable "container_soft_delete_retention_days" {
  description = "Days deleted containers are retained for recovery."
  type        = number
  default     = 7

  validation {
    condition     = var.container_soft_delete_retention_days >= 1 && var.container_soft_delete_retention_days <= 365
    error_message = "container_soft_delete_retention_days must be between 1 and 365."
  }
}

variable "containers" {
  description = "Names of blob containers to create in the storage account. Containers are always private: anonymous access is disabled at the account level, and readers authorise with Microsoft Entra ID and RBAC."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for name in var.containers : length(name) >= 3 && length(name) <= 63 && can(regex("^[a-z0-9](-?[a-z0-9])*$", name))])
    error_message = "Container names must be 3-63 characters of lowercase letters, numbers and single hyphens, starting and ending alphanumeric."
  }
}

variable "file_shares" {
  description = "Azure file shares to create in the storage account, keyed by name. SMB only: NFS shares need a Premium FileStorage account, which this general purpose module does not create."
  type = map(object({
    quota_in_gb      = number
    access_tier      = optional(string, "TransactionOptimized")
    enabled_protocol = optional(string, "SMB")
  }))
  default = {}

  validation {
    condition     = alltrue([for name, share in var.file_shares : share.quota_in_gb >= 1 && share.quota_in_gb <= 102400])
    error_message = "File share quotas must be between 1 and 102400 GB."
  }

  validation {
    condition     = alltrue([for name, share in var.file_shares : share.enabled_protocol == "SMB"])
    error_message = "File shares must use SMB: NFS needs a Premium FileStorage account, which this StorageV2 module does not create."
  }
}

variable "azure_files_authentication" {
  description = "Identity-based authentication for the account's SMB file shares. AADKERB (Microsoft Entra Kerberos) lets Entra joined machines mount shares without domain controllers - after the first deployment an administrator must grant admin consent to the storage account's auto-created Entra application, and share access is granted with the Azure Files data plane RBAC roles. AD (on-premises Active Directory) requires the active_directory block. Leave null to keep identity-based file share access off."
  type = object({
    directory_type                 = string
    default_share_level_permission = optional(string)
    active_directory = optional(object({
      domain_name         = string
      domain_guid         = string
      domain_sid          = optional(string)
      storage_sid         = optional(string)
      forest_name         = optional(string)
      netbios_domain_name = optional(string)
    }))
  })
  default = null

  validation {
    condition     = var.azure_files_authentication == null ? true : contains(["AADKERB", "AD", "AADDS"], var.azure_files_authentication.directory_type)
    error_message = "azure_files_authentication.directory_type must be AADKERB, AD or AADDS."
  }

  validation {
    condition     = var.azure_files_authentication == null ? true : (var.azure_files_authentication.directory_type != "AD" || var.azure_files_authentication.active_directory != null)
    error_message = "azure_files_authentication with directory_type AD requires the active_directory block."
  }
}

variable "backup" {
  description = "Registers the account's blob data with a Data Protection backup vault. Leave null to skip backup."
  type = object({
    backup_vault_id           = string
    backup_vault_principal_id = string
    backup_policy_id          = string
  })
  default = null
}

variable "log_analytics_workspace_id" {
  description = "The ID of a Log Analytics workspace to send blob and queue service request logs and metrics to. Leave null to skip diagnostics."
  type        = string
  default     = null
}

variable "enable_diagnostics" {
  description = "Whether to create the blob and queue service diagnostic settings. Defaults to creating them when log_analytics_workspace_id is set. Set explicitly when the workspace is created in the same apply: its ID is unknown at plan time, so it cannot decide whether the settings exist."
  type        = bool
  default     = null

  validation {
    condition     = var.enable_diagnostics != true || var.log_analytics_workspace_id != null
    error_message = "enable_diagnostics requires log_analytics_workspace_id to be set."
  }
}

variable "tags" {
  description = "Tags applied to the storage account."
  type        = map(string)
  default     = {}
}

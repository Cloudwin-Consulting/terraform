variable "name" {
  description = "The name of the virtual machine."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the virtual machine is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the virtual machine is deployed."
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet the virtual machine's network interface is attached to."
  type        = string
}

variable "size" {
  description = "The size of the virtual machine."
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "The admin username for the virtual machine."
  type        = string
  default     = "azureadmin"
}

variable "admin_ssh_public_key" {
  description = "The SSH public key used to authenticate as the admin user. Password authentication is disabled."
  type        = string

  validation {
    condition     = can(regex("^ssh-", var.admin_ssh_public_key))
    error_message = "admin_ssh_public_key must be an OpenSSH public key, e.g. starting with ssh-rsa or ssh-ed25519."
  }
}

variable "zone" {
  description = "The availability zone of the virtual machine and its disks. Leave null for a regional deployment."
  type        = string
  default     = null

  validation {
    condition     = var.zone == null || contains(["1", "2", "3"], coalesce(var.zone, "1"))
    error_message = "zone must be 1, 2 or 3."
  }
}

variable "os_disk" {
  description = "Settings of the operating system disk, including optional customer-managed key encryption through a disk encryption set."
  type = object({
    caching                = optional(string, "ReadWrite")
    storage_account_type   = optional(string, "StandardSSD_LRS")
    disk_size_gb           = optional(number)
    disk_encryption_set_id = optional(string)
  })
  default = {}
}

variable "data_disks" {
  description = "Managed data disks created and attached to the virtual machine, in LUN order. Disks default to private-only access and support customer-managed key encryption through a disk encryption set."
  type = list(object({
    name                          = string
    disk_size_gb                  = number
    storage_account_type          = optional(string, "StandardSSD_LRS")
    caching                       = optional(string, "ReadWrite")
    tier                          = optional(string)
    disk_encryption_set_id        = optional(string)
    network_access_policy         = optional(string, "DenyAll")
    public_network_access_enabled = optional(bool, false)
    disk_access_id                = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for disk in var.data_disks : disk.disk_size_gb >= 1 && disk.disk_size_gb <= 65536 && contains(["AllowAll", "AllowPrivate", "DenyAll"], disk.network_access_policy)])
    error_message = "Data disks must be 1-65536 GB with a network_access_policy of AllowAll, AllowPrivate or DenyAll."
  }
}

variable "source_image_id" {
  description = "The ID of a compute gallery image (or image version) the virtual machine is created from. Overrides source_image_reference when set."
  type        = string
  default     = null
}

variable "backup" {
  description = "Protects the virtual machine with a Recovery Services vault backup policy. Leave null to skip backup."
  type = object({
    recovery_vault_name                = string
    recovery_vault_resource_group_name = string
    backup_policy_id                   = string
  })
  default = null
}

variable "monitor_agent" {
  description = "Installs the Azure Monitor Agent. Set data_collection_rule_id to associate an existing rule, or log_analytics_workspace_id to create a default one. Set data_collection_endpoint_id when the workspace only ingests over private link. Set create_data_collection_rule and associate_data_collection_endpoint explicitly when those IDs come from resources created in the same apply, because unknown IDs cannot decide the agent module's counts. Leave null to skip the agent."
  type = object({
    data_collection_rule_id            = optional(string)
    log_analytics_workspace_id         = optional(string)
    data_collection_endpoint_id        = optional(string)
    create_data_collection_rule        = optional(bool)
    associate_data_collection_endpoint = optional(bool)
  })
  default = null
}

variable "source_image_reference" {
  description = "The marketplace image the virtual machine is created from. The default requires a generation 2 image for trusted launch."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

variable "secure_boot_enabled" {
  description = "Whether trusted launch secure boot is enabled."
  type        = bool
  default     = true
}

variable "vtpm_enabled" {
  description = "Whether the trusted launch virtual TPM is enabled."
  type        = bool
  default     = true
}

variable "encryption_at_host_enabled" {
  description = "Whether encryption at host is enabled. Requires the Microsoft.Compute/EncryptionAtHost subscription feature."
  type        = bool
  default     = true
}

variable "patch_mode" {
  description = "The in-guest patching mode of the virtual machine."
  type        = string
  default     = "ImageDefault"

  validation {
    condition     = contains(["ImageDefault", "AutomaticByPlatform"], var.patch_mode)
    error_message = "patch_mode must be ImageDefault or AutomaticByPlatform for Linux."
  }
}

variable "tags" {
  description = "Tags applied to the virtual machine resources."
  type        = map(string)
  default     = {}
}

variable "application_security_group_ids" {
  description = "IDs of application security groups the machine's network interface joins, so subnet NSG rules can target the workload by membership instead of IP address."
  type        = list(string)
  default     = []
}

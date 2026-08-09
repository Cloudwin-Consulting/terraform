variable "name" {
  description = "The name of the session host virtual machine."
  type        = string
}

variable "computer_name" {
  description = "The in-guest computer name, at most 15 characters. Leave null to use the virtual machine name, which must then fit the limit itself."
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "The resource group into which the session host is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the session host is deployed."
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet the session host's network interface is attached to."
  type        = string
}

variable "size" {
  description = "The size of the session host."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "admin_username" {
  description = "The break-glass local admin username. Users sign in with their Microsoft Entra credentials instead."
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "The break-glass local admin password. Generate it rather than committing it to source control."
  type        = string
  sensitive   = true
}

variable "host_pool_name" {
  description = "The name of the host pool the session host registers into. The host pool must be in the same Azure region as the machine."
  type        = string
}

variable "host_pool_id" {
  description = "The ID of the host pool the session host registers into, from the avd-host-pool module's id output. Only used to detect that the pool itself was replaced - a Pooled to Personal switch re-creates it under the same name - so the host registers again into the replacement."
  type        = string
}

variable "registration_token" {
  description = "The host pool registration token, from the avd-host-pool module's registration_token output."
  type        = string
  sensitive   = true
}

variable "avd_agent_package_url" {
  description = "The URL of the AVD agent DSC configuration package the registration extension pulls. The default tracks the latest package the AVD portal deploys; pin a versioned package URL for repeatable builds."
  type        = string
  default     = "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration.zip"
}

variable "intune_mdm_id" {
  description = "The MDM application ID that enrols the machine into Intune alongside the Microsoft Entra join, i.e. 0000000a-0000-0000-c000-000000000000. Leave null to join Entra ID without Intune enrolment."
  type        = string
  default     = null
}

variable "zone" {
  description = "The availability zone of the session host and its disks. Leave null for a regional deployment."
  type        = string
  default     = null
}

variable "os_disk" {
  description = "Settings of the operating system disk, including optional customer-managed key encryption through a disk encryption set. Session hosts are stateless - user profiles belong on an FSLogix profile share - so no data disks are attached."
  type = object({
    caching                = optional(string, "ReadWrite")
    storage_account_type   = optional(string, "StandardSSD_LRS")
    disk_size_gb           = optional(number)
    disk_encryption_set_id = optional(string)
  })
  default = {}
}

variable "source_image_id" {
  description = "The ID of a compute gallery image (or image version) the session host is created from, e.g. a golden image with applications baked in. Overrides source_image_reference when set."
  type        = string
  default     = null
}

variable "source_image_reference" {
  description = "The marketplace image the session host is created from. The default is Windows 11 multi-session with Microsoft 365 Apps."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "office-365"
    sku       = "win11-24h2-avd-m365"
    version   = "latest"
  }
}

variable "license_type" {
  description = "The licence applied through Azure Hybrid Benefit. Windows_Client covers session hosts whose users hold eligible Microsoft 365 or Windows per-user licences - the usual AVD licensing - so it is the default; set null for pay-as-you-go."
  type        = string
  default     = "Windows_Client"
}

variable "secure_boot_enabled" {
  description = "Whether trusted launch secure boot is enabled. The marketplace multi-session images support trusted launch; set false alongside vtpm_enabled when source_image_id points at a generation 1 image, or a generation 2 image built without it, which Azure otherwise refuses to deploy."
  type        = bool
  default     = true
}

variable "vtpm_enabled" {
  description = "Whether the trusted launch virtual TPM is enabled. Set false alongside secure_boot_enabled for images that do not support trusted launch."
  type        = bool
  default     = true
}

variable "encryption_at_host_enabled" {
  description = "Whether encryption at host is enabled. Requires the Microsoft.Compute/EncryptionAtHost subscription feature."
  type        = bool
  default     = true
}

variable "application_security_group_ids" {
  description = "IDs of application security groups the session host's network interface joins, so subnet NSG rules can target the workload by membership instead of IP address."
  type        = list(string)
  default     = []
}

variable "monitor_agent" {
  description = "Installs the Azure Monitor Agent, which AVD Insights uses for session host performance data. Set data_collection_rule_id to associate an existing rule, or log_analytics_workspace_id to create a default one. Set data_collection_endpoint_id when the workspace only ingests over private link. Set create_data_collection_rule and associate_data_collection_endpoint explicitly when those IDs come from resources created in the same apply, because unknown IDs cannot decide the agent module's counts. Leave null to skip the agent."
  type = object({
    data_collection_rule_id            = optional(string)
    log_analytics_workspace_id         = optional(string)
    data_collection_endpoint_id        = optional(string)
    create_data_collection_rule        = optional(bool)
    associate_data_collection_endpoint = optional(bool)
  })
  default = null
}

variable "tags" {
  description = "Tags applied to the session host resources."
  type        = map(string)
  default     = {}
}

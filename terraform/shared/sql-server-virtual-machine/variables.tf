variable "name" {
  description = "The name of the virtual machine."
  type        = string

  validation {
    condition     = var.computer_name != null || length(var.name) <= 15
    error_message = "Set computer_name when the virtual machine name exceeds the 15 character Windows computer name limit."
  }
}

variable "computer_name" {
  description = "The in-guest computer name, at most 15 characters. Leave null to use the virtual machine name, which must then fit the limit itself. SQL Server takes its instance name from this, so renaming it later means renaming the instance."
  type        = string
  default     = null

  validation {
    condition     = var.computer_name == null || can(regex("^[a-zA-Z0-9-]{1,15}$", coalesce(var.computer_name, "x")))
    error_message = "computer_name must be at most 15 characters of letters, numbers and hyphens."
  }
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
  description = "The size of the virtual machine. SQL Server workloads want a memory-optimised size with enough attached-disk throughput for the data and log disks, e.g. Standard_E4ds_v5."
  type        = string
  default     = "Standard_E4ds_v5"
}

variable "admin_username" {
  description = "The local administrator username for the virtual machine."
  type        = string
  default     = "azureadmin"
}

variable "admin_password" {
  description = "The local administrator password for the virtual machine. Generate it or read it from a key vault rather than committing it to source control."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 12 && length(var.admin_password) <= 123
    error_message = "Windows admin passwords must be between 12 and 123 characters."
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
  description = "Settings of the operating system disk, including optional customer-managed key encryption through a disk encryption set. Keep SQL Server's own files off this disk and on the data disks below."
  type = object({
    caching                = optional(string, "ReadWrite")
    storage_account_type   = optional(string, "StandardSSD_LRS")
    disk_size_gb           = optional(number)
    disk_encryption_set_id = optional(string)
  })
  default = {}
}

variable "data_disks" {
  description = <<-EOT
    Managed data disks created, attached and then laid out by the SQL IaaS Agent extension.

    Each disk declares the LUN it attaches at and the role its volume serves: `data` for database files, `log` for transaction logs and `temp_db` for tempdb. Disks sharing a role are pooled into one volume, so multiple disks per role is the way to scale throughput past a single disk's limits.

    The storage layout is addressed by the LUNs declared here, not by the disks' position in the list, so reordering or removing a disk never silently relabels the volumes underneath a running instance. Changing a LUN on a deployed disk detaches and reattaches it, so treat LUNs as fixed once a machine is in service.

    Leave caching unset to get Microsoft's guidance for the role: ReadOnly for data and tempdb, None for log (host caching on a log volume can lose writes the log has already acknowledged).

    Disks default to private-only access and support customer-managed key encryption through a disk encryption set.
  EOT

  type = list(object({
    name                          = string
    disk_size_gb                  = number
    lun                           = number
    role                          = optional(string, "data")
    storage_account_type          = optional(string, "Premium_LRS")
    caching                       = optional(string)
    tier                          = optional(string)
    disk_encryption_set_id        = optional(string)
    network_access_policy         = optional(string, "DenyAll")
    public_network_access_enabled = optional(bool, false)
    disk_access_id                = optional(string)
  }))

  default = [
    {
      name         = "data"
      disk_size_gb = 256
      lun          = 1
      role         = "data"
    },
    {
      name         = "log"
      disk_size_gb = 128
      lun          = 2
      role         = "log"
    },
  ]

  validation {
    condition     = alltrue([for disk in var.data_disks : contains(["data", "log", "temp_db"], disk.role)])
    error_message = "Each data disk's role must be data, log or temp_db."
  }

  validation {
    condition     = length(distinct([for disk in var.data_disks : disk.name])) == length(var.data_disks)
    error_message = "Data disk names must be unique within the virtual machine."
  }

  validation {
    condition     = length(distinct([for disk in var.data_disks : disk.lun])) == length(var.data_disks)
    error_message = "Each data disk must have a unique LUN: the SQL storage configuration addresses the volumes by LUN, so a duplicate would put two disks in the same slot."
  }

  validation {
    condition     = alltrue([for disk in var.data_disks : disk.lun >= 0 && disk.lun <= 63])
    error_message = "Data disk LUNs must be between 0 and 63."
  }

  validation {
    condition     = alltrue([for disk in var.data_disks : disk.disk_size_gb >= 1 && disk.disk_size_gb <= 65536])
    error_message = "Data disks must be between 1 and 65536 GB."
  }

  validation {
    condition     = alltrue([for disk in var.data_disks : disk.caching == null || contains(["None", "ReadOnly", "ReadWrite"], coalesce(disk.caching, "None"))])
    error_message = "Data disk caching must be None, ReadOnly or ReadWrite."
  }

  validation {
    condition     = alltrue([for disk in var.data_disks : disk.role != "log" || coalesce(disk.caching, "None") == "None"])
    error_message = "Log disks must use None caching: host caching on a transaction log volume risks losing writes SQL Server has already acknowledged. Leave caching unset to get the right value for the role."
  }

  validation {
    condition     = alltrue([for disk in var.data_disks : contains(["AllowAll", "AllowPrivate", "DenyAll"], disk.network_access_policy)])
    error_message = "Data disk network_access_policy must be AllowAll, AllowPrivate or DenyAll."
  }

  validation {
    condition     = length(var.data_disks) == 0 || length([for disk in var.data_disks : disk if disk.role == "data"]) > 0
    error_message = "At least one data disk must have the data role: SQL Server needs somewhere to put its database files."
  }
}

variable "storage_configuration" {
  description = <<-EOT
    How the SQL IaaS Agent extension lays SQL Server's files out over the volumes it builds from the data disks.

    The default file paths assume the extension's usual drive letters, assigned in role order from F: - data on F:, log on G: and tempdb on H:. Adjust them to match the volumes an existing machine already has when disk_type is EXTEND or ADD.

    storage_workload_type tunes the extension's disk and instance settings for the workload: GENERAL, OLTP (transaction processing) or DW (data warehousing).
  EOT

  type = object({
    disk_type                      = optional(string, "NEW")
    storage_workload_type          = optional(string, "GENERAL")
    system_db_on_data_disk_enabled = optional(bool, false)
    data_file_path                 = optional(string, "F:\\data")
    log_file_path                  = optional(string, "G:\\log")
    temp_db_file_path              = optional(string, "H:\\tempDb")
    temp_db = optional(object({
      data_file_count        = optional(number)
      data_file_size_mb      = optional(number)
      data_file_growth_in_mb = optional(number)
      log_file_size_mb       = optional(number)
      log_file_growth_mb     = optional(number)
    }))
  })

  default = {}

  validation {
    condition     = contains(["NEW", "EXTEND", "ADD"], var.storage_configuration.disk_type)
    error_message = "storage_configuration.disk_type must be NEW, EXTEND or ADD."
  }

  validation {
    condition     = contains(["GENERAL", "OLTP", "DW"], var.storage_configuration.storage_workload_type)
    error_message = "storage_configuration.storage_workload_type must be GENERAL, OLTP or DW."
  }

  validation {
    condition = alltrue([
      for path in [
        var.storage_configuration.data_file_path,
        var.storage_configuration.log_file_path,
        var.storage_configuration.temp_db_file_path,
      ] : can(regex("^[A-Za-z]:\\\\", path))
    ])
    error_message = "storage_configuration file paths must be absolute Windows paths on a drive letter, e.g. F:\\data."
  }
}

variable "sql_license_type" {
  description = "How the SQL Server licence is paid for: PAYG for pay-as-you-go, AHUB to bring a licence covered by Software Assurance through Azure Hybrid Benefit, or DR for a passive disaster recovery replica. Ignored by the free developer and express editions."
  type        = string
  default     = "PAYG"

  validation {
    condition     = contains(["PAYG", "AHUB", "DR"], var.sql_license_type)
    error_message = "sql_license_type must be PAYG, AHUB or DR."
  }
}

variable "sql_connectivity_type" {
  description = "How far SQL Server's TCP listener reaches: LOCAL for the machine itself only, PRIVATE for the virtual network, or PUBLIC for the internet. Keep PRIVATE (or LOCAL) and reach the instance over the private network - PUBLIC exposes the database engine to the internet."
  type        = string
  default     = "PRIVATE"

  validation {
    condition     = contains(["LOCAL", "PRIVATE", "PUBLIC"], var.sql_connectivity_type)
    error_message = "sql_connectivity_type must be LOCAL, PRIVATE or PUBLIC."
  }
}

variable "sql_connectivity_port" {
  description = "The TCP port SQL Server listens on. A non-default port is worth setting when the instance is reachable beyond the machine."
  type        = number
  default     = 1433

  validation {
    condition     = var.sql_connectivity_port >= 1 && var.sql_connectivity_port <= 65535
    error_message = "sql_connectivity_port must be between 1 and 65535."
  }
}

variable "sql_login" {
  description = "A SQL Server authentication login created by the agent, and with it mixed mode authentication. Leave null - the secure default - so the instance keeps Windows authentication only, and grant access to domain or Entra ID principals instead. Only set this for workloads that cannot use Windows authentication."
  type = object({
    username = string
    password = string
  })
  default   = null
  sensitive = true

  validation {
    condition     = var.sql_login == null || length(try(var.sql_login.password, "")) >= 12
    error_message = "The SQL login password must be at least 12 characters."
  }

  validation {
    condition     = var.sql_login == null || !contains(["sa", "admin", "administrator", "sqladmin", "root"], lower(try(var.sql_login.username, "")))
    error_message = "The SQL login username must not be a well-known account name such as sa or admin."
  }
}

variable "r_services_enabled" {
  description = "Whether SQL Server Machine Learning Services (R and Python) is enabled. Keep disabled unless the workload needs it: it runs external scripts on the database host."
  type        = bool
  default     = false
}

variable "sql_instance" {
  description = "Instance-level SQL Server settings applied by the agent, e.g. collation, degree of parallelism and the memory ceiling. Leave null to keep SQL Server's own defaults. Setting max_server_memory_mb is worth doing on a dedicated machine so the engine leaves the operating system room to breathe."
  type = object({
    collation                            = optional(string)
    max_dop                              = optional(number)
    min_server_memory_mb                 = optional(number)
    max_server_memory_mb                 = optional(number)
    instant_file_initialization_enabled  = optional(bool)
    lock_pages_in_memory_enabled         = optional(bool)
    adhoc_workloads_optimization_enabled = optional(bool)
  })
  default = null

  validation {
    condition     = var.sql_instance == null || try(var.sql_instance.max_server_memory_mb, null) == null || try(var.sql_instance.min_server_memory_mb, 0) <= try(var.sql_instance.max_server_memory_mb, 0)
    error_message = "sql_instance.min_server_memory_mb must not exceed max_server_memory_mb."
  }
}

variable "auto_patching" {
  description = "The weekly maintenance window in which the agent applies SQL Server and Windows updates. On by default, because an unpatched database engine is the likeliest way one of these machines is compromised. Set to null to take patching over yourself, which also returns the guest to the AutomaticByOS patch mode unless patch_mode says otherwise."
  type = object({
    day_of_week                            = optional(string, "Sunday")
    maintenance_window_starting_hour       = optional(number, 2)
    maintenance_window_duration_in_minutes = optional(number, 60)
  })
  default = {}

  validation {
    condition     = var.auto_patching == null || contains(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday", "Everyday"], try(var.auto_patching.day_of_week, "Sunday"))
    error_message = "auto_patching.day_of_week must be a day name or Everyday."
  }

  validation {
    condition     = var.auto_patching == null || (try(var.auto_patching.maintenance_window_starting_hour, 2) >= 0 && try(var.auto_patching.maintenance_window_starting_hour, 2) <= 23)
    error_message = "auto_patching.maintenance_window_starting_hour must be between 0 and 23."
  }

  validation {
    condition     = var.auto_patching == null || (try(var.auto_patching.maintenance_window_duration_in_minutes, 60) >= 30 && try(var.auto_patching.maintenance_window_duration_in_minutes, 60) <= 180)
    error_message = "auto_patching.maintenance_window_duration_in_minutes must be between 30 and 180."
  }
}

variable "auto_backup" {
  description = "SQL Server's own backups, written to a storage account by the agent. Backups are always encrypted: supply encryption_password, and hold it somewhere durable, because a backup cannot be restored without it. The storage account needs shared key authorisation enabled, since the agent authenticates with an access key rather than a managed identity. Leave manual_schedule null to let the agent schedule backups from the log growth it observes. Leave the whole variable null to rely on machine-level backup through var.backup instead."
  type = object({
    retention_period_in_days        = number
    storage_blob_endpoint           = string
    storage_account_access_key      = string
    encryption_password             = string
    system_databases_backup_enabled = optional(bool, true)
    manual_schedule = optional(object({
      full_backup_frequency           = string
      full_backup_start_hour          = number
      full_backup_window_in_hours     = number
      log_backup_frequency_in_minutes = number
      days_of_week                    = optional(set(string))
    }))
  })
  default   = null
  sensitive = true

  validation {
    condition     = var.auto_backup == null || (try(var.auto_backup.retention_period_in_days, 0) >= 1 && try(var.auto_backup.retention_period_in_days, 0) <= 30)
    error_message = "auto_backup.retention_period_in_days must be between 1 and 30."
  }

  validation {
    condition     = var.auto_backup == null || length(try(var.auto_backup.encryption_password, "")) >= 12
    error_message = "auto_backup.encryption_password must be at least 12 characters: SQL auto backups are always encrypted so the blobs are useless to anyone who reaches the storage account."
  }

  validation {
    condition     = var.auto_backup == null || try(var.auto_backup.manual_schedule, null) == null || contains(["Daily", "Weekly"], try(var.auto_backup.manual_schedule.full_backup_frequency, ""))
    error_message = "auto_backup.manual_schedule.full_backup_frequency must be Daily or Weekly."
  }
}

variable "assessment" {
  description = "Runs the SQL best practices assessment, which reports configuration and security findings into the Log Analytics workspace the machine's monitor agent sends to. Requires var.monitor_agent to be configured. Leave null to skip the assessment."
  type = object({
    enabled         = optional(bool, true)
    run_immediately = optional(bool, false)
    schedule = optional(object({
      day_of_week        = string
      start_time         = string
      weekly_interval    = optional(number)
      monthly_occurrence = optional(number)
    }))
  })
  default = null

  validation {
    condition     = var.assessment == null || try(var.assessment.schedule, null) == null || contains(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"], try(var.assessment.schedule.day_of_week, ""))
    error_message = "assessment.schedule.day_of_week must be a day name."
  }

  validation {
    condition     = var.assessment == null || try(var.assessment.schedule, null) == null || can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", try(var.assessment.schedule.start_time, "")))
    error_message = "assessment.schedule.start_time must be a 24 hour HH:MM time."
  }
}

variable "key_vault_credential" {
  description = "Points the SQL Server Connector at a key vault, so transparent data encryption, backup encryption and column encryption can use customer-managed keys held there instead of keys on the machine. The service principal needs get, list, wrapKey, unwrapKey, sign and verify on the vault's keys. Leave null to keep SQL Server's service-managed keys."
  type = object({
    name                     = string
    key_vault_url            = string
    service_principal_name   = string
    service_principal_secret = string
  })
  default   = null
  sensitive = true
}

variable "sql_virtual_machine_group_id" {
  description = "The ID of the SQL virtual machine group this machine joins for an Always On availability group. Requires wsfc_domain_credential. Leave null for a standalone instance."
  type        = string
  default     = null

  validation {
    condition     = var.sql_virtual_machine_group_id == null || var.wsfc_domain_credential != null
    error_message = "Joining a SQL virtual machine group requires wsfc_domain_credential: the cluster needs its service account passwords."
  }
}

variable "wsfc_domain_credential" {
  description = "Passwords of the Windows Server Failover Cluster service accounts, used when the machine joins an Always On availability group. The machine must already be domain joined. Leave null for a standalone instance."
  type = object({
    cluster_bootstrap_account_password = string
    cluster_operator_account_password  = string
    sql_service_account_password       = string
  })
  default   = null
  sensitive = true
}

variable "source_image_id" {
  description = "The ID of a compute gallery image (or image version) the virtual machine is created from, e.g. a hardened SQL Server build. Overrides source_image_reference when set."
  type        = string
  default     = null
}

variable "source_image_reference" {
  description = "The marketplace image the virtual machine is created from. The default is SQL Server 2022 Standard on Windows Server 2022; the SKU must be a generation 2 image for trusted launch. Use a -ws2022 offer with an enterprise-gen2, standard-gen2, web-gen2 or sqldev-gen2 SKU."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftSQLServer"
    offer     = "sql2022-ws2022"
    sku       = "standard-gen2"
    version   = "latest"
  }
}

variable "backup" {
  description = "Protects the whole virtual machine with a Recovery Services vault backup policy. This is machine-level backup and is application consistent, but it is not a SQL log backup chain: use var.auto_backup, or Azure Backup's SQL workload protection, when point-in-time restore matters. Leave null to skip."
  type = object({
    recovery_vault_name                = string
    recovery_vault_resource_group_name = string
    backup_policy_id                   = string
  })
  default = null
}

variable "monitor_agent" {
  description = "Installs the Azure Monitor Agent. Set data_collection_rule_id to associate an existing rule, or log_analytics_workspace_id to create a default one. Set data_collection_endpoint_id when the workspace only ingests over private link. Set create_data_collection_rule and associate_data_collection_endpoint explicitly when those IDs come from resources created in the same apply, because unknown IDs cannot decide the agent module's counts. Required for var.assessment. Leave null to skip the agent."
  type = object({
    data_collection_rule_id            = optional(string)
    log_analytics_workspace_id         = optional(string)
    data_collection_endpoint_id        = optional(string)
    create_data_collection_rule        = optional(bool)
    associate_data_collection_endpoint = optional(bool)
  })
  default = null
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
  description = "Whether encryption at host is enabled, encrypting the machine's disk and temp disk data in the host cache as well as at rest. Requires the Microsoft.Compute/EncryptionAtHost subscription feature."
  type        = bool
  default     = true
}

variable "license_type" {
  description = "The existing Windows Server licence applied through Azure Hybrid Benefit. SQL Server's own licence is set with sql_license_type. Leave null for pay-as-you-go."
  type        = string
  default     = null

  validation {
    condition     = var.license_type == null || contains(["Windows_Server", "Windows_Client"], coalesce(var.license_type, "Windows_Server"))
    error_message = "license_type must be Windows_Server, Windows_Client or null."
  }
}

variable "patch_mode" {
  description = "The guest's Windows patching mode. Leave null to let the module decide: Manual while auto_patching drives the maintenance window through the SQL IaaS agent, otherwise AutomaticByOS."
  type        = string
  default     = null

  validation {
    condition     = var.patch_mode == null || contains(["Manual", "AutomaticByOS", "AutomaticByPlatform"], coalesce(var.patch_mode, "Manual"))
    error_message = "patch_mode must be Manual, AutomaticByOS or AutomaticByPlatform."
  }
}

variable "application_security_group_ids" {
  description = "IDs of application security groups the machine's network interface joins, so subnet NSG rules can target the database tier by membership instead of IP address."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the virtual machine resources."
  type        = map(string)
  default     = {}
}

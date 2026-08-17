terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# SQL Server running on a Windows Server virtual machine, registered
# with the SQL IaaS Agent extension so Azure manages its licensing,
# patching, storage layout and backups.
#
# The machine itself comes from the windows-virtual-machine module, so
# it inherits that module's secure defaults unchanged: no public IP
# address, trusted launch (secure boot and vTPM), encryption at host,
# a system-assigned identity and optional application security group
# membership. Reach it over the private network, e.g. through Azure
# Bastion in the hub.

locals {
  # Microsoft's storage guidance for SQL Server on Azure virtual
  # machines: read-heavy data files benefit from the host read cache,
  # while log files must never be host-cached because a host failure
  # can lose writes the log has already acknowledged. Callers can
  # still set caching per disk; these only fill in the blanks.
  default_caching_by_role = {
    data    = "ReadOnly"
    log     = "None"
    temp_db = "ReadOnly"
  }

  # The disks handed to the virtual machine module, which attaches
  # each one at the LUN it declares.
  data_disks = [
    for disk in var.data_disks : merge(disk, {
      caching = coalesce(disk.caching, local.default_caching_by_role[disk.role])
    })
  ]

  # The LUNs backing each storage role, taken from the disks
  # themselves rather than their position in the list, so reordering
  # or removing a disk never silently relabels the volumes underneath
  # a running instance. A role with no disks gets an empty list and
  # its settings block is left out entirely.
  luns_by_role = {
    for role in keys(local.default_caching_by_role) :
    role => [for disk in var.data_disks : disk.lun if disk.role == role]
  }

  # SQL Server's own automated patching drives the maintenance window
  # through the IaaS agent, so the guest's Windows Update is left in
  # manual mode rather than patching the machine out from under it.
  # An explicit patch_mode always wins.
  patch_mode = coalesce(var.patch_mode, var.auto_patching == null ? "AutomaticByOS" : "Manual")
}

module "virtual_machine" {
  source = "../windows-virtual-machine"

  name                = var.name
  computer_name       = var.computer_name
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id
  size                = var.size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  zone                = var.zone
  tags                = var.tags

  application_security_group_ids = var.application_security_group_ids

  secure_boot_enabled        = var.secure_boot_enabled
  vtpm_enabled               = var.vtpm_enabled
  encryption_at_host_enabled = var.encryption_at_host_enabled
  patch_mode                 = local.patch_mode
  license_type               = var.license_type

  os_disk    = var.os_disk
  data_disks = local.data_disks

  source_image_id        = var.source_image_id
  source_image_reference = var.source_image_reference

  backup        = var.backup
  monitor_agent = var.monitor_agent
}

# Registers the machine with the SQL IaaS Agent extension in full
# management mode.
#
# The extension formats and mounts the data disks attached above, so
# it depends on the whole virtual machine module rather than just the
# machine's ID: the disk attachments have to be in place before the
# storage configuration can address them by LUN.
resource "azurerm_mssql_virtual_machine" "this" {
  depends_on = [module.virtual_machine]

  virtual_machine_id = module.virtual_machine.id
  tags               = var.tags

  # Secure defaults: reachable only from inside the virtual network
  # (never the public internet), no SQL logins unless the caller asks
  # for one, and the R/Machine Learning services left off so the
  # in-database script host is not exposed.
  sql_connectivity_type            = var.sql_connectivity_type
  sql_connectivity_port            = var.sql_connectivity_port
  sql_connectivity_update_username = var.sql_login == null ? null : var.sql_login.username
  sql_connectivity_update_password = var.sql_login == null ? null : var.sql_login.password
  r_services_enabled               = var.r_services_enabled

  sql_license_type             = var.sql_license_type
  sql_virtual_machine_group_id = var.sql_virtual_machine_group_id

  # Lays SQL Server's files out across the attached disks: data files
  # on the data-role disks, transaction logs on the log-role disks and
  # tempdb on its own, each on the volume the extension builds from
  # those LUNs.
  dynamic "storage_configuration" {
    for_each = length(var.data_disks) > 0 ? [var.storage_configuration] : []

    content {
      disk_type                      = storage_configuration.value.disk_type
      storage_workload_type          = storage_configuration.value.storage_workload_type
      system_db_on_data_disk_enabled = storage_configuration.value.system_db_on_data_disk_enabled

      dynamic "data_settings" {
        for_each = length(local.luns_by_role.data) > 0 ? [1] : []

        content {
          default_file_path = storage_configuration.value.data_file_path
          luns              = local.luns_by_role.data
        }
      }

      dynamic "log_settings" {
        for_each = length(local.luns_by_role.log) > 0 ? [1] : []

        content {
          default_file_path = storage_configuration.value.log_file_path
          luns              = local.luns_by_role.log
        }
      }

      dynamic "temp_db_settings" {
        for_each = length(local.luns_by_role.temp_db) > 0 ? [1] : []

        content {
          default_file_path      = storage_configuration.value.temp_db_file_path
          luns                   = local.luns_by_role.temp_db
          data_file_count        = try(storage_configuration.value.temp_db.data_file_count, null)
          data_file_size_mb      = try(storage_configuration.value.temp_db.data_file_size_mb, null)
          data_file_growth_in_mb = try(storage_configuration.value.temp_db.data_file_growth_in_mb, null)
          log_file_size_mb       = try(storage_configuration.value.temp_db.log_file_size_mb, null)
          log_file_growth_mb     = try(storage_configuration.value.temp_db.log_file_growth_mb, null)
        }
      }
    }
  }

  # Instance-level settings applied by the agent, e.g. the collation,
  # memory ceiling and instant file initialisation.
  dynamic "sql_instance" {
    for_each = var.sql_instance == null ? [] : [var.sql_instance]

    content {
      collation                            = sql_instance.value.collation
      max_dop                              = sql_instance.value.max_dop
      min_server_memory_mb                 = sql_instance.value.min_server_memory_mb
      max_server_memory_mb                 = sql_instance.value.max_server_memory_mb
      instant_file_initialization_enabled  = sql_instance.value.instant_file_initialization_enabled
      lock_pages_in_memory_enabled         = sql_instance.value.lock_pages_in_memory_enabled
      adhoc_workloads_optimization_enabled = sql_instance.value.adhoc_workloads_optimization_enabled
    }
  }

  # Automated patching of SQL Server and Windows inside the agent's
  # maintenance window. On by default: unpatched database engines are
  # the most common way one of these machines gets compromised.
  dynamic "auto_patching" {
    for_each = var.auto_patching == null ? [] : [var.auto_patching]

    content {
      day_of_week                            = auto_patching.value.day_of_week
      maintenance_window_starting_hour       = auto_patching.value.maintenance_window_starting_hour
      maintenance_window_duration_in_minutes = auto_patching.value.maintenance_window_duration_in_minutes
    }
  }

  # SQL Server's own backups to a storage account, always encrypted:
  # the variable's validation refuses an auto backup without an
  # encryption password. Machine-level backup through a Recovery
  # Services vault is configured separately with var.backup.
  # The guards below only unwrap whether a sensitive block was
  # configured at all, never the values inside it: a sensitive value
  # cannot decide a for_each, but "is auto backup switched on" is not
  # itself a secret.
  dynamic "auto_backup" {
    for_each = nonsensitive(var.auto_backup == null) ? [] : [1]

    content {
      retention_period_in_days        = var.auto_backup.retention_period_in_days
      storage_blob_endpoint           = var.auto_backup.storage_blob_endpoint
      storage_account_access_key      = var.auto_backup.storage_account_access_key
      system_databases_backup_enabled = var.auto_backup.system_databases_backup_enabled
      encryption_enabled              = true
      encryption_password             = var.auto_backup.encryption_password

      dynamic "manual_schedule" {
        for_each = nonsensitive(var.auto_backup.manual_schedule == null) ? [] : [1]

        content {
          full_backup_frequency           = var.auto_backup.manual_schedule.full_backup_frequency
          full_backup_start_hour          = var.auto_backup.manual_schedule.full_backup_start_hour
          full_backup_window_in_hours     = var.auto_backup.manual_schedule.full_backup_window_in_hours
          log_backup_frequency_in_minutes = var.auto_backup.manual_schedule.log_backup_frequency_in_minutes
          days_of_week                    = var.auto_backup.manual_schedule.days_of_week
        }
      }
    }
  }

  # Runs the SQL best practices assessment on a schedule, reporting
  # into the Log Analytics workspace the machine's monitor agent
  # sends to.
  dynamic "assessment" {
    for_each = var.assessment == null ? [] : [var.assessment]

    content {
      enabled         = assessment.value.enabled
      run_immediately = assessment.value.run_immediately

      dynamic "schedule" {
        for_each = assessment.value.schedule == null ? [] : [assessment.value.schedule]

        content {
          day_of_week        = schedule.value.day_of_week
          start_time         = schedule.value.start_time
          weekly_interval    = schedule.value.weekly_interval
          monthly_occurrence = schedule.value.monthly_occurrence
        }
      }
    }
  }

  # Points the SQL Server Connector at a key vault so transparent data
  # encryption and backup encryption can use customer-managed keys
  # held there rather than keys on the machine.
  dynamic "key_vault_credential" {
    for_each = nonsensitive(var.key_vault_credential == null) ? [] : [1]

    content {
      name                     = var.key_vault_credential.name
      key_vault_url            = var.key_vault_credential.key_vault_url
      service_principal_name   = var.key_vault_credential.service_principal_name
      service_principal_secret = var.key_vault_credential.service_principal_secret
    }
  }

  # Service account passwords for a Windows Server Failover Cluster,
  # used when the machine joins an Always On availability group.
  dynamic "wsfc_domain_credential" {
    for_each = nonsensitive(var.wsfc_domain_credential == null) ? [] : [1]

    content {
      cluster_bootstrap_account_password = var.wsfc_domain_credential.cluster_bootstrap_account_password
      cluster_operator_account_password  = var.wsfc_domain_credential.cluster_operator_account_password
      sql_service_account_password       = var.wsfc_domain_credential.sql_service_account_password
    }
  }
}

deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "sql-server-vm"
environment                = "prod"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "sql-server-vm"
environment_tag     = "Production"
owner               = "CloudEngineering"
cost_center         = "sql-server-vm"
criticality         = "High"
service             = "Data"
data_classification = "Confidential"
lifecycle_stage     = "Permanent"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

app_spoke_subscription_id       = null
app_spoke_deployment_name       = "app-spoke"
application_security_group_role = "sql-server"

hub_subscription_id = null
hub_deployment_name = "hub-spoke"

monitoring_subscription_id    = null
monitoring_deployment_name    = "monitoring-spoke"
data_collection_endpoint_name = null

sql_image_sku        = "standard-gen2"
virtual_machine_size = "Standard_E8ds_v5"

# A single zonal instance. Highly available production databases need
# an Always On availability group across zones: build the second
# machine as its own deployment and join both to a SQL virtual machine
# group through the shared module's availability group inputs.
virtual_machine_count = 1
availability_zones    = ["1"]

# The Windows licence comes from Software Assurance through Azure
# Hybrid Benefit; SQL Server itself stays pay-as-you-go until a
# licence with Software Assurance is assigned to it, at which point
# sql_license_type becomes AHUB.
license_type     = "Windows_Server"
sql_license_type = "PAYG"

# ------------------------------------------------------------
# Storage
#
# The data volume is striped across two premium disks, because a
# single disk caps out well below what the machine can drive. The log
# gets its own disk with host caching off, and tempdb its own disk
# again, so none of the three compete for the same queue.
# ------------------------------------------------------------
data_disks = [
  {
    name                 = "data1"
    disk_size_gb         = 512
    role                 = "data"
    storage_account_type = "Premium_LRS"
  },
  {
    name                 = "data2"
    disk_size_gb         = 512
    role                 = "data"
    storage_account_type = "Premium_LRS"
  },
  {
    name                 = "log"
    disk_size_gb         = 256
    role                 = "log"
    storage_account_type = "Premium_LRS"
  },
  {
    name                 = "tempdb"
    disk_size_gb         = 256
    role                 = "temp_db"
    storage_account_type = "Premium_LRS"
  },
]

storage_configuration = {
  storage_workload_type = "OLTP"

  temp_db = {
    data_file_count        = 8
    data_file_size_mb      = 2048
    data_file_growth_in_mb = 512
    log_file_size_mb       = 2048
    log_file_growth_mb     = 512
  }
}

# Leaves the operating system and the SQL IaaS agent room to breathe
# on a 64 GB machine rather than letting the buffer pool take it all.
sql_instance = {
  max_server_memory_mb                = 57344
  instant_file_initialization_enabled = true
  lock_pages_in_memory_enabled        = true
}

# ------------------------------------------------------------
# Protection and monitoring
# ------------------------------------------------------------
enable_backup                         = true
backup_private_endpoint_dns_zone_name = "privatelink.uks.backup.windowsazure.com"
backup_daily_retention_days           = 30
enable_monitor_agent                  = true

# The best practices assessment reports configuration and security
# findings into the monitoring workspace every week.
enable_assessment = true
assessment_schedule = {
  day_of_week     = "Sunday"
  start_time      = "23:00"
  weekly_interval = 1
}

auto_patching = {
  day_of_week                            = "Sunday"
  maintenance_window_starting_hour       = 2
  maintenance_window_duration_in_minutes = 120
}

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
database_subnet_name         = "snet-database"
private_endpoint_subnet_name = "snet-private-endpoints"
computer_name                = "sqlvm"

# Set this to read the local administrator password from a secret
# pre-loaded into the spoke's platform key vault, instead of having
# the deployment generate one into Terraform state. The plan then has
# to run on an agent inside the network.
# admin_password_key_vault_secret = {
#   secret_name = "sql-server-vm-admin-password"
# }
admin_password_key_vault_secret = null

os_disk           = {}
sql_image_offer   = "sql2022-ws2022"
sql_image_version = "latest"
source_image_id   = null

# Windows authentication only: grant access to domain groups rather
# than creating SQL logins.
sql_connectivity_type     = "PRIVATE"
sql_connectivity_port     = 1433
enable_sql_authentication = false
sql_login_username        = "sqlappadmin"
r_services_enabled        = false

secure_boot_enabled                     = true
vtpm_enabled                            = true
encryption_at_host_enabled              = true
key_vault_name                          = null
key_vault_secrets_officer_principal_ids = []
platform_key_vault_subscription_id      = null
tags                                    = {}

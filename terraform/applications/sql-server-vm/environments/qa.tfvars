deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "sql-server-vm"
environment                = "qa"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "sql-server-vm"
environment_tag     = "QA"
owner               = "CloudEngineering"
cost_center         = "sql-server-vm"
criticality         = "Medium"
service             = "Data"
data_classification = "Confidential"
lifecycle_stage     = "Temporary"
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

# QA runs the same edition as production so licensing and behaviour
# match what is being tested, on a smaller machine.
sql_image_sku        = "standard-gen2"
virtual_machine_size = "Standard_E2ds_v5"

# Premium disks with the same data, log and tempdb split as
# production, so query plans and IO behaviour are comparable.
data_disks = [
  {
    name         = "data"
    disk_size_gb = 256
    lun          = 0
    role         = "data"
  },
  {
    name         = "log"
    disk_size_gb = 128
    lun          = 1
    role         = "log"
  },
  {
    name         = "tempdb"
    disk_size_gb = 128
    lun          = 2
    role         = "temp_db"
  },
]

storage_configuration = {
  storage_workload_type = "OLTP"
}

# Backed up and monitored so restores and alerting are exercised
# before production depends on them.
enable_backup                         = true
backup_private_endpoint_dns_zone_name = "privatelink.uks.backup.windowsazure.com"
backup_daily_retention_days           = 14
enable_monitor_agent                  = true
enable_assessment                     = true

assessment_schedule = {
  day_of_week     = "Sunday"
  start_time      = "23:00"
  weekly_interval = 1
}

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
database_subnet_name            = "snet-database"
private_endpoint_subnet_name    = "snet-private-endpoints"
virtual_machine_count           = 1
computer_name                   = "sqlvm"
admin_password_key_vault_secret = null
availability_zones              = []
license_type                    = null
os_disk                         = {}
sql_image_offer                 = "sql2022-ws2022"
sql_image_version               = "latest"
source_image_id                 = null
sql_license_type                = "PAYG"
sql_connectivity_type           = "PRIVATE"
sql_connectivity_port           = 1433
enable_sql_authentication       = false
sql_login_username              = "sqlappadmin"
r_services_enabled              = false
sql_instance                    = null
auto_patching = {
  day_of_week                            = "Sunday"
  maintenance_window_starting_hour       = 2
  maintenance_window_duration_in_minutes = 60
}
secure_boot_enabled                     = true
vtpm_enabled                            = true
encryption_at_host_enabled              = true
key_vault_name                          = null
key_vault_secrets_officer_principal_ids = []
platform_key_vault_subscription_id      = null
tags                                    = {}

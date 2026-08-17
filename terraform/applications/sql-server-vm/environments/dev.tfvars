deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "sql-server-vm"
environment                = "dev"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "sql-server-vm"
environment_tag     = "Development"
owner               = "CloudEngineering"
cost_center         = "sql-server-vm"
criticality         = "Low"
service             = "Data"
data_classification = "Internal"
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

monitoring_subscription_id = null
monitoring_deployment_name = "monitoring-spoke"

# The free developer edition carries no SQL licence cost and is
# feature-identical to Enterprise. It is never licensed for
# production use.
sql_image_sku        = "sqldev-gen2"
virtual_machine_size = "Standard_E2ds_v5"

data_disks = [
  {
    name                 = "data"
    disk_size_gb         = 128
    lun                  = 0
    role                 = "data"
    storage_account_type = "StandardSSD_LRS"
  },
  {
    name                 = "log"
    disk_size_gb         = 64
    lun                  = 1
    role                 = "log"
    storage_account_type = "StandardSSD_LRS"
  },
]

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
storage_configuration           = {}
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
enable_assessment                       = false
assessment_schedule                     = null
enable_backup                           = false
backup_private_endpoint_dns_zone_name   = null
backup_daily_retention_days             = 7
enable_monitor_agent                    = false
data_collection_endpoint_name           = null
secure_boot_enabled                     = true
vtpm_enabled                            = true
encryption_at_host_enabled              = true
key_vault_name                          = null
key_vault_secrets_officer_principal_ids = []
platform_key_vault_subscription_id      = null
tags                                    = {}

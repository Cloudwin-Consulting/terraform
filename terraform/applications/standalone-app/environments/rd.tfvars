deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "standalone-app"
environment                = "rd"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "standalone-app"
environment_tag     = "RD"
owner               = "CloudEngineering"
cost_center         = "standalone-app"
criticality         = "Low"
service             = "ApplicationPlatform"
data_classification = "Internal"
lifecycle_stage     = "Sandbox"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

# ------------------------------------------------------------
# Network
#
# The same ranges are used in every environment, because each
# environment is deployed into its own subscription. Nothing here
# peers: a platform hub peers to this network from its own side, so
# take the address space from whoever runs that hub.
# ------------------------------------------------------------
address_space = ["10.241.0.0/22"]
dns_servers   = []

subnets = {
  "snet-private-endpoints" = {
    address_prefixes = ["10.241.0.0/24"]
  }
  "snet-virtual-machines" = {
    address_prefixes = ["10.241.1.0/24"]
  }
  "snet-app-service" = {
    address_prefixes = ["10.241.2.0/26"]
    delegation = {
      name         = "appservice"
      service_name = "Microsoft.Web/serverFarms"
    }
  }
}

# SSH and RDP reach the machines from the platform hub's Azure Bastion
# subnet and nowhere else.
management_source_address_prefixes = ["10.240.0.128/26"]

# ------------------------------------------------------------
# Private DNS
#
# This stack owns the privatelink zones its endpoints need and links
# them to its own network. Where the platform owns a zone centrally,
# name it in existing_private_dns_zone_ids instead; where the platform
# registers endpoints with an Azure Policy assignment, set
# create_private_dns_zones = false and leave the map empty.
# ------------------------------------------------------------
create_private_dns_zones      = true
existing_private_dns_zone_ids = {}

# ------------------------------------------------------------
# Virtual machines
#
# R&D runs one machine in each tier, regionally, on burstable sizes.
# ------------------------------------------------------------
linux_virtual_machine_count   = 1
windows_virtual_machine_count = 1
availability_zones            = []

linux_virtual_machine_size   = "Standard_B2s"
windows_virtual_machine_size = "Standard_B2s"

# Password authentication is disabled on the Linux tier. A public key
# is not a secret, so it is held here rather than in a key vault.
linux_admin_ssh_public_key = "ssh-rsa <replace_with_admin_ssh_public_key>"

windows_data_disks = [
  {
    name         = "data"
    disk_size_gb = 32
  }
]

# Backup is off outside QA and production: the machines here are
# rebuilt from this configuration rather than restored.
enable_backup                         = false
backup_private_endpoint_dns_zone_name = null
backup_storage_mode_type              = "GeoRedundant"
backup_daily_retention_days           = 7

# ------------------------------------------------------------
# Azure SQL
#
# R&D puts every database on a single serverless server, which pauses
# when nobody is using it.
# ------------------------------------------------------------
sql_server_count = 1

sql_entra_admin_login_username = "<entra_admin_login>"
sql_entra_admin_object_id      = "<entra_admin_object_id>"

sql_databases = {
  appdb = {
    sku_name                    = "GP_S_Gen5_1"
    max_size_gb                 = 32
    auto_pause_delay_in_minutes = 60
  }
}

# ------------------------------------------------------------
# Web app
# ------------------------------------------------------------
enable_app_service                 = true
app_service_sku                    = "B1"
app_service_worker_count           = 1
app_service_zone_balancing_enabled = false

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
private_endpoint_subnet_name = "snet-private-endpoints"
virtual_machine_subnet_name  = "snet-virtual-machines"
app_service_subnet_name      = "snet-app-service"
application_tier_port_ranges = ["8080"]
monitor_private_dns_zone_names = [
  "privatelink.monitor.azure.com",
  "privatelink.oms.opinsights.azure.com",
  "privatelink.ods.opinsights.azure.com",
  "privatelink.agentsvc.azure-automation.net",
]
enable_private_monitoring               = true
enable_monitor_agent                    = true
log_retention_in_days                   = 30
log_daily_quota_gb                      = null
application_insights_retention_in_days  = 90
key_vault_name                          = null
key_vault_secrets_officer_principal_ids = []
storage_account_name                    = null
storage_replication_type                = "ZRS"
storage_containers                      = ["app-data"]
secure_boot_enabled                     = true
vtpm_enabled                            = true
encryption_at_host_enabled              = true
linux_virtual_machine_role              = "web"
linux_admin_username                    = "azureadmin"
linux_os_disk                           = {}
linux_data_disks                        = []
linux_source_image_id                   = null
windows_virtual_machine_role            = "app"
windows_admin_username                  = "azureadmin"
windows_computer_name_prefix            = "appsrv"
windows_license_type                    = null
windows_os_disk                         = {}
windows_source_image_id                 = null
sql_server_name_prefix                  = null
web_app_name                            = null
app_service_application_stack = {
  dotnet_version = "8.0"
}
app_service_app_settings = {}
tags                     = {}

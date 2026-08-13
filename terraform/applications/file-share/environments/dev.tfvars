deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "file-share"
environment                = "dev"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "file-share"
environment_tag     = "Development"
owner               = "CloudEngineering"
cost_center         = "file-share"
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
application_security_group_role = "windows-vm"

hub_subscription_id = null
hub_deployment_name = "hub-spoke"

monitoring_subscription_id = null
monitoring_deployment_name = "monitoring-spoke"

storage_account_replication_type = "LRS"
file_share_quota_gb              = 100

virtual_machine_size = "Standard_B2s"

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
virtual_machine_subnet_name  = "snet-windows-vm"
private_endpoint_subnet_name = "snet-private-endpoints"

storage_account_name    = null
file_share_name         = "appdata"
file_share_access_tier  = "TransactionOptimized"
file_share_drive_letter = "F"

# No directory to authenticate against in this environment, so the
# machines mount the share with the account key (kept in state and
# delivered as an encrypted protected parameter). The share-level
# roles below only apply once identity-based authentication is on.
azure_files_authentication   = null
share_contributor_principals = {}
share_admin_principals       = {}
share_principal_type         = "Group"

virtual_machine_count              = 1
computer_name                      = "vmappfiles"
platform_key_vault_subscription_id = null
admin_password_key_vault_secret    = null
domain_join                        = null
availability_zones                 = []
os_disk                            = {}
source_image_id                    = null
secure_boot_enabled                = true
vtpm_enabled                       = true
encryption_at_host_enabled         = true
enable_monitor_agent               = false
data_collection_endpoint_name      = null
tags                               = {}

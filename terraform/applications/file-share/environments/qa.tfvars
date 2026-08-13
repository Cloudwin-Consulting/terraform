deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "file-share"
environment                = "qa"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "file-share"
environment_tag     = "QA"
owner               = "CloudEngineering"
cost_center         = "file-share"
criticality         = "Medium"
service             = "Data"
data_classification = "Internal"
lifecycle_stage     = "Permanent"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

app_spoke_subscription_id       = null
app_spoke_deployment_name       = "app-spoke"
application_security_group_role = "windows-vm"

hub_subscription_id = null
hub_deployment_name = "hub-spoke"

monitoring_subscription_id    = null
monitoring_deployment_name    = "monitoring-spoke"
data_collection_endpoint_name = null

# QA rehearses the production shape at a smaller size: a zone
# redundant share and a second machine, so the mount is exercised on
# more than one machine at a time.
storage_account_replication_type = "ZRS"
file_share_quota_gb              = 512

virtual_machine_size  = "Standard_D2s_v5"
virtual_machine_count = 2
availability_zones    = ["1", "2"]
enable_monitor_agent  = true

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

computer_name                      = "vmappfiles"
platform_key_vault_subscription_id = null
admin_password_key_vault_secret    = null
domain_join                        = null
os_disk                            = {}
source_image_id                    = null
secure_boot_enabled                = true
vtpm_enabled                       = true
encryption_at_host_enabled         = true
tags                               = {}

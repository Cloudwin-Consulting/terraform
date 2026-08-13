deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "file-share"
environment                = "prod"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "file-share"
environment_tag     = "Production"
owner               = "CloudEngineering"
cost_center         = "file-share"
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
application_security_group_role = "windows-vm"

hub_subscription_id = null
hub_deployment_name = "hub-spoke"

monitoring_subscription_id    = null
monitoring_deployment_name    = "monitoring-spoke"
data_collection_endpoint_name = null

# Production keeps the application's files on a zone redundant share
# an order of magnitude larger than the sandbox one, and spreads the
# machines that write to it across zones. The share stays reachable
# through the loss of a datacentre, and the files outlive any machine.
storage_account_replication_type = "ZRS"
file_share_quota_gb              = 2048

virtual_machine_size  = "Standard_D2s_v5"
virtual_machine_count = 3
availability_zones    = ["1", "2", "3"]
enable_monitor_agent  = true

# Identity-based authentication, so no account key exists for these
# files: uncomment both blocks together and the machines mount the
# share as their own Active Directory computer accounts, authorised by
# the default share-level permission below. Two prerequisites, both
# outside Terraform: create the storage account's AD account with the
# AzFilesHybrid PowerShell module (which is where domain_guid and the
# SIDs come from), and pre-load the join account's credentials into
# the spoke's platform key vault (secrets domain-join-username and
# domain-join-password). The machines also have to reach the domain -
# see the application spoke's dns_servers and
# active_directory_outbound_address_prefixes.
#
# azure_files_authentication = {
#   directory_type                 = "AD"
#   default_share_level_permission = "StorageFileDataSmbShareContributor"
#   active_directory = {
#     domain_name         = "corp.example.com"
#     domain_guid         = "<domain_guid>"
#     domain_sid          = "<domain_sid>"
#     storage_sid         = "<storage_account_sid>"
#     forest_name         = "corp.example.com"
#     netbios_domain_name = "CORP"
#   }
# }
#
# domain_join = {
#   domain_name          = "corp.example.com"
#   ou_path              = "OU=Servers,DC=corp,DC=example,DC=com"
#   username_secret_name = "domain-join-username"
#   password_secret_name = "domain-join-password"
# }

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

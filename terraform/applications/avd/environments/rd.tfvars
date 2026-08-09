deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "avd"
environment                = "rd"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "avd"
environment_tag     = "RD"
owner               = "CloudEngineering"
cost_center         = "avd"
criticality         = "Low"
service             = "EndUserComputing"
data_classification = "Internal"
lifecycle_stage     = "Sandbox"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

app_spoke_deployment_name       = "app-spoke"
application_security_group_role = "windows-vm"

hub_deployment_name = "hub-spoke"

monitoring_deployment_name = "monitoring-spoke"

session_host_size = "Standard_D2s_v5"

# Set to a Microsoft Entra ID group's object ID to entitle its members
# to the desktop; without it the desktop deploys but no user can see
# or sign in to it.
avd_users_group_object_id = null

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
session_host_subnet_name     = "snet-windows-vm"
private_endpoint_subnet_name = "snet-private-endpoints"
host_pool_type               = "Pooled"
host_pool_load_balancer_type = "BreadthFirst"
maximum_sessions_allowed     = 8
host_pool_friendly_name      = null
workspace_friendly_name      = null
desktop_friendly_name        = "Desktop"
start_vm_on_connect          = false
validate_environment         = false
custom_rdp_properties        = "targetisaadjoined:i:1;drivestoredirect:s:;redirectclipboard:i:0;redirectprinters:i:0"
session_host_count           = 1
computer_name_prefix         = "vmavd"
availability_zones           = []
os_disk                      = {}
source_image_id              = null
source_image_reference = {
  publisher = "MicrosoftWindowsDesktop"
  offer     = "office-365"
  sku       = "win11-24h2-avd-m365"
  version   = "latest"
}
encryption_at_host_enabled       = true
license_type                     = "Windows_Client"
avd_service_principal_object_id  = null
enable_scaling_plan              = false
scaling_plan_time_zone           = "GMT Standard Time"
scaling_plan_schedules           = null
enable_fslogix                   = true
fslogix_storage_account_name     = null
fslogix_storage_replication_type = "ZRS"
fslogix_admins_group_object_id   = null
fslogix_profiles_share_quota_gb  = 100
enable_monitor_agent             = false
data_collection_endpoint_name    = null
app_spoke_subscription_id        = null
hub_subscription_id              = null
monitoring_subscription_id       = null
tags                             = {}

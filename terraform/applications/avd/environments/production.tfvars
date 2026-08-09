deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "avd"
environment                = "prod"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "avd"
environment_tag     = "Production"
owner               = "CloudEngineering"
cost_center         = "avd"
criticality         = "High"
service             = "EndUserComputing"
data_classification = "Confidential"
lifecycle_stage     = "Permanent"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

app_spoke_deployment_name       = "app-spoke"
application_security_group_role = "windows-vm"

hub_deployment_name = "hub-spoke"

monitoring_deployment_name    = "monitoring-spoke"
data_collection_endpoint_name = null

session_host_size = "Standard_D4s_v5"

# Production scales out across availability zones and follows the
# working day: the scaling plan ramps hosts up ahead of it and
# deallocates them in the evening, and a user connecting off-hours
# starts a host on demand. Both need the Azure Virtual Desktop service
# principal's object ID (look it up with
# `az ad sp show --id 9cdead84-a844-4324-93f2-b2e6bb768d07 --query id`).
session_host_count              = 3
availability_zones              = ["1", "2", "3"]
enable_scaling_plan             = true
start_vm_on_connect             = true
avd_service_principal_object_id = "<avd_service_principal_object_id>"

# Production session hosts are monitored through the Azure Monitor
# Agent, completing AVD Insights alongside the host pool logs.
enable_monitor_agent = true

# Set to a Microsoft Entra ID group's object ID to entitle its members
# to the desktop; without it the desktop deploys but no user can see
# or sign in to it.
avd_users_group_object_id = null

# Profile storage sized for the pool's concurrent users.
fslogix_profiles_share_quota_gb = 512

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
validate_environment         = false
custom_rdp_properties        = "targetisaadjoined:i:1;drivestoredirect:s:;redirectclipboard:i:0;redirectprinters:i:0"
computer_name_prefix         = "vmavd"
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
scaling_plan_time_zone           = "GMT Standard Time"
scaling_plan_schedules           = null
enable_fslogix                   = true
fslogix_storage_account_name     = null
fslogix_storage_replication_type = "ZRS"
fslogix_admins_group_object_id   = null
app_spoke_subscription_id        = null
hub_subscription_id              = null
monitoring_subscription_id       = null
tags                             = {}

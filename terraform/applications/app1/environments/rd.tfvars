deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "app1"
environment                = "rd"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "app1"
environment_tag     = "RD"
owner               = "CloudEngineering"
cost_center         = "app1"
criticality         = "Low"
service             = "ApplicationPlatform"
data_classification = "Internal"
lifecycle_stage     = "Sandbox"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

app_spoke_subscription_id = null
app_spoke_deployment_name = "app-spoke"

hub_subscription_id = null
hub_deployment_name = "hub-spoke"

monitoring_subscription_id = null
monitoring_deployment_name = "monitoring-spoke"

app_service_sku = "B1"

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
app_integration_subnet_name             = "snet-app1-integration"
private_endpoint_subnet_name            = "snet-private-endpoints"
app_service_worker_count                = 1
app_service_zone_balancing_enabled      = false
web_app_name                            = null
storage_account_name                    = null
enable_storage_backup                   = false
key_vault_name                          = null
key_vault_secrets_officer_principal_ids = []
enable_front_door_endpoint              = false
front_door_profile_name                 = null
front_door_endpoint_name                = null
enable_traffic_manager                  = false
traffic_manager_dns_name                = null
tags                                    = {}

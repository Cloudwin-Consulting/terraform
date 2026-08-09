deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "app2"
environment                = "prod"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "app2"
environment_tag     = "Production"
owner               = "CloudEngineering"
cost_center         = "app2"
criticality         = "High"
service             = "ApplicationPlatform"
data_classification = "Confidential"
lifecycle_stage     = "Permanent"
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

app_service_sku = "P1v3"

# Spread the plan's workers across availability zones.
app_service_worker_count           = 3
app_service_zone_balancing_enabled = true

# Production blob data is registered with a backup vault.
enable_storage_backup = true

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
app_integration_subnet_name             = "snet-app2-integration"
private_endpoint_subnet_name            = "snet-private-endpoints"
web_app_name                            = null
storage_account_name                    = null
key_vault_name                          = null
key_vault_secrets_officer_principal_ids = []
enable_front_door_endpoint              = false
front_door_profile_name                 = null
front_door_endpoint_name                = null
tags                                    = {}

deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "cms"
environment                = "prod"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "cms"
environment_tag     = "Production"
owner               = "CloudEngineering"
cost_center         = "cms"
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

# Pre-load the database password into the spoke's platform key vault
# (Secrets Officer, from inside the network) before deploying. The
# deployment bootstraps MySQL with it and the running app resolves the
# same secret at runtime.
database_password_key_vault_secret = {
  secret_name = "cms-database-password"
}

# Production runs general purpose MySQL with zone-redundant HA and a
# zone-balanced Premium plan.
mysql_sku                   = "GP_Standard_D2ds_v4"
mysql_backup_retention_days = 35
mysql_high_availability = {
  mode = "ZoneRedundant"
}

app_service_sku                    = "P1v3"
app_service_worker_count           = 3
app_service_zone_balancing_enabled = true

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
integration_subnet_name            = "snet-cms-integration"
mysql_subnet_name                  = "snet-mysql"
private_endpoint_subnet_name       = "snet-private-endpoints"
mysql_server_name                  = null
database_name                      = "cms"
media_storage_account_name         = null
web_app_name                       = null
platform_key_vault_subscription_id = null
tags                               = {}

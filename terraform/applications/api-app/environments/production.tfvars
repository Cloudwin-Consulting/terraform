deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "api-app"
environment                = "prod"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "api-app"
environment_tag     = "Production"
owner               = "CloudEngineering"
cost_center         = "api-app"
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
# (Secrets Officer, from inside the network) before deploying.
database_password_key_vault_secret = {
  secret_name = "api-app-database-password"
}

# Production runs general purpose PostgreSQL with zone-redundant HA,
# a zoned Premium cache and a zone-balanced Premium plan.
postgresql_sku = "GP_Standard_D2ds_v5"
postgresql_high_availability = {
  mode = "ZoneRedundant"
}
postgresql_backup_retention_days = 35

redis_sku      = "Premium"
redis_family   = "P"
redis_capacity = 1
redis_zones    = ["1", "2", "3"]

app_service_sku                    = "P1v3"
app_service_worker_count           = 3
app_service_zone_balancing_enabled = true

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
integration_subnet_name                 = "snet-api-integration"
postgresql_subnet_name                  = "snet-postgresql"
private_endpoint_subnet_name            = "snet-private-endpoints"
postgresql_server_name                  = null
postgresql_storage_mb                   = 32768
postgresql_entra_administrator          = null
database_name                           = "api"
redis_name                              = null
app_configuration_name                  = null
app_configuration_sku                   = "standard"
web_app_name                            = null
key_vault_name                          = null
key_vault_secrets_officer_principal_ids = []
platform_key_vault_subscription_id      = null
tags                                    = {}

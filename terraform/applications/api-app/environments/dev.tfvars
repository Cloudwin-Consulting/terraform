deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "api-app"
environment                = "dev"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "api-app"
environment_tag     = "Development"
owner               = "CloudEngineering"
cost_center         = "api-app"
criticality         = "Low"
service             = "ApplicationPlatform"
data_classification = "Internal"
lifecycle_stage     = "Temporary"
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

# Cost-effective sizing outside production.
postgresql_sku  = "B_Standard_B1ms"
redis_sku       = "Standard"
redis_family    = "C"
redis_capacity  = 1
app_service_sku = "B1"

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
integration_subnet_name                 = "snet-api-integration"
postgresql_subnet_name                  = "snet-postgresql"
private_endpoint_subnet_name            = "snet-private-endpoints"
postgresql_server_name                  = null
postgresql_storage_mb                   = 32768
postgresql_backup_retention_days        = 7
postgresql_high_availability            = null
postgresql_entra_administrator          = null
database_name                           = "api"
redis_name                              = null
redis_zones                             = null
app_configuration_name                  = null
app_configuration_sku                   = "standard"
web_app_name                            = null
app_service_worker_count                = 1
app_service_zone_balancing_enabled      = false
key_vault_name                          = null
key_vault_secrets_officer_principal_ids = []
platform_key_vault_subscription_id      = null
tags                                    = {}

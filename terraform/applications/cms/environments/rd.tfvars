deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "cms"
environment                = "rd"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "cms"
environment_tag     = "RD"
owner               = "CloudEngineering"
cost_center         = "cms"
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

# Pre-load the database password into the spoke's platform key vault
# (Secrets Officer, from inside the network) before deploying. The
# deployment bootstraps MySQL with it and the running app resolves the
# same secret at runtime.
database_password_key_vault_secret = {
  secret_name = "cms-database-password"
}

# Cost-effective sizing outside production.
mysql_sku       = "B_Standard_B1ms"
app_service_sku = "B1"

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
integration_subnet_name            = "snet-cms-integration"
mysql_subnet_name                  = "snet-mysql"
private_endpoint_subnet_name       = "snet-private-endpoints"
mysql_server_name                  = null
mysql_backup_retention_days        = 7
mysql_high_availability            = null
database_name                      = "cms"
media_storage_account_name         = null
web_app_name                       = null
app_service_worker_count           = 1
app_service_zone_balancing_enabled = false
platform_key_vault_subscription_id = null
tags                               = {}

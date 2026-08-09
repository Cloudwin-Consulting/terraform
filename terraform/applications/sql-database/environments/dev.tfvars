deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "sql-database"
environment                = "dev"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "sql-database"
environment_tag     = "Development"
owner               = "CloudEngineering"
cost_center         = "sql-database"
criticality         = "Low"
service             = "Data"
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

sql_entra_admin_login_username = "<entra_admin_login>"
sql_entra_admin_object_id      = "<entra_admin_object_id>"

database_sku = "GP_S_Gen5_1"

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
private_endpoint_subnet_name         = "snet-private-endpoints"
sql_server_name                      = null
database_name                        = "appdb"
database_auto_pause_delay_in_minutes = 60
database_max_size_gb                 = 32
database_zone_redundant              = false
tags                                 = {}

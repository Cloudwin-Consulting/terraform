deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "function-app"
environment                = "dev"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "function-app"
environment_tag     = "Development"
owner               = "CloudEngineering"
cost_center         = "function-app"
criticality         = "Low"
service             = "Integration"
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

function_app_sku = "B1"

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
app_integration_subnet_name                = "snet-func-integration"
private_endpoint_subnet_name               = "snet-private-endpoints"
function_app_worker_count                  = 1
function_app_zone_balancing_enabled        = false
service_bus_capacity                       = 1
function_app_name                          = null
storage_account_name                       = null
service_bus_name                           = null
key_vault_name                             = null
key_vault_secrets_officer_principal_ids    = []
pim_operations_principals                  = {}
pim_operations_role_definition_name        = "Contributor"
pim_operations_maximum_activation_duration = "PT8H"
tags                                       = {}

deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "logic-app"
environment                = "prod"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "logic-app"
environment_tag     = "Production"
owner               = "CloudEngineering"
cost_center         = "logic-app"
criticality         = "High"
service             = "Integration"
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

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
app_integration_subnet_name             = "snet-logic-integration"
private_endpoint_subnet_name            = "snet-private-endpoints"
logic_app_sku                           = "WS1"
logic_app_name                          = null
storage_account_name                    = null
key_vault_name                          = null
key_vault_secrets_officer_principal_ids = []
tags                                    = {}

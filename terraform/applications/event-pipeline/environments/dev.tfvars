deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "event-pipeline"
environment                = "dev"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "event-pipeline"
environment_tag     = "Development"
owner               = "CloudEngineering"
cost_center         = "event-pipeline"
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

# Cost-effective sizing outside production.
event_hub_partition_count = 2
function_app_sku          = "EP1"

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
integration_subnet_name                 = "snet-eventpipe-integration"
private_endpoint_subnet_name            = "snet-private-endpoints"
event_hub_namespace_name                = null
event_hub_sku                           = "Standard"
event_hub_capacity                      = 1
event_hub_auto_inflate_enabled          = false
event_hub_maximum_throughput_units      = null
event_hub_message_retention             = 1
cosmos_account_name                     = null
cosmos_database_name                    = "telemetry"
cosmos_container_name                   = "events"
cosmos_zone_redundant                   = false
cosmos_automatic_failover_enabled       = false
cosmos_additional_geo_locations         = []
function_app_name                       = null
function_app_worker_count               = 1
function_app_zone_balancing_enabled     = false
storage_account_name                    = null
key_vault_name                          = null
key_vault_secrets_officer_principal_ids = []
tags                                    = {}

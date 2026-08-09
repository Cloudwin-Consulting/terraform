deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "event-pipeline"
environment                = "prod"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "event-pipeline"
environment_tag     = "Production"
owner               = "CloudEngineering"
cost_center         = "event-pipeline"
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

# Production scales ingestion with auto-inflate, spreads the account
# across zones, fails over to a secondary region and zone-balances the
# consumer.
event_hub_capacity                 = 2
event_hub_auto_inflate_enabled     = true
event_hub_maximum_throughput_units = 10
event_hub_partition_count          = 8
event_hub_message_retention        = 3

cosmos_zone_redundant             = true
cosmos_automatic_failover_enabled = true
cosmos_additional_geo_locations = [
  {
    location = "ukwest"
  }
]

function_app_sku                    = "EP2"
function_app_worker_count           = 2
function_app_zone_balancing_enabled = true

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
integration_subnet_name                 = "snet-eventpipe-integration"
private_endpoint_subnet_name            = "snet-private-endpoints"
event_hub_namespace_name                = null
event_hub_sku                           = "Standard"
cosmos_account_name                     = null
cosmos_database_name                    = "telemetry"
cosmos_container_name                   = "events"
function_app_name                       = null
storage_account_name                    = null
key_vault_name                          = null
key_vault_secrets_officer_principal_ids = []
tags                                    = {}

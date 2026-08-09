deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "container-apps"
environment                = "dev"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "container-apps"
environment_tag     = "Development"
owner               = "CloudEngineering"
cost_center         = "container-apps"
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

min_replicas = 1
max_replicas = 3

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
container_apps_subnet_name                 = "snet-container-apps"
private_endpoint_subnet_name               = "snet-private-endpoints"
zone_redundancy_enabled                    = false
container_image                            = "mcr.microsoft.com/k8se/quickstart:latest"
container_target_port                      = 80
container_cpu                              = 0.25
container_memory                           = "0.5Gi"
container_registry_name                    = null
container_registry_zone_redundancy_enabled = false
container_registry_push_principal_ids      = []
key_vault_name                             = null
key_vault_secrets_officer_principal_ids    = []
tags                                       = {}

deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "front-door-example"
environment                = "qa"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "front-door-example"
environment_tag     = "QA"
owner               = "CloudEngineering"
cost_center         = "front-door-example"
criticality         = "Medium"
service             = "EntryPoint"
data_classification = "Internal"
lifecycle_stage     = "Temporary"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

front_door_sku = "Standard_AzureFrontDoor"

# Dummy origins: the profile deploys complete and reports both origins
# unhealthy until these hostnames point at something real.
front_door_endpoints = {
  primary = {
    origin_host_name  = "placeholder-primary.example.com"
    health_probe_path = "/healthz"
  }

  secondary = {
    origin_host_name  = "placeholder-secondary.example.com"
    health_probe_path = "/healthz"
  }
}

enable_diagnostics         = true
monitoring_deployment_name = "monitoring-spoke"

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
front_door_name                     = null
front_door_response_timeout_seconds = 60
monitoring_subscription_id          = null
tags                                = {}

deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "front-door-example"
environment                = "prod"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "front-door-example"
environment_tag     = "Production"
owner               = "CloudEngineering"
cost_center         = "front-door-example"
criticality         = "High"
service             = "EntryPoint"
data_classification = "Confidential"
lifecycle_stage     = "Permanent"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

# Premium is what a real production profile needs: it is the only SKU
# that reaches an origin over Private Link, so the origin can keep
# public network access disabled.
front_door_sku = "Premium_AzureFrontDoor"

# Dummy origins: the profile deploys complete and reports both origins
# unhealthy until these hostnames point at something real. Replace them
# with the workload's origins - and, on this SKU, add the
# front-door-endpoint module's private_link block so the origins stay
# off the public internet.
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

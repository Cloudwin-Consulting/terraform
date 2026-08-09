deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "traffic-manager-example"
environment                = "dev"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "traffic-manager-example"
environment_tag     = "Development"
owner               = "CloudEngineering"
cost_center         = "traffic-manager-example"
criticality         = "Low"
service             = "EntryPoint"
data_classification = "Internal"
lifecycle_stage     = "Temporary"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

# Dummy endpoints, served without probing so the profile answers
# queries before any real target exists. Replace the targets and turn
# always_serve_enabled off to have Traffic Manager fail traffic away
# from an unhealthy endpoint.
external_endpoints = [
  {
    name                 = "primary"
    target               = "placeholder-primary.example.com"
    priority             = 1
    weight               = 100
    always_serve_enabled = true
  },
  {
    name                 = "secondary"
    target               = "placeholder-secondary.example.com"
    priority             = 2
    weight               = 100
    always_serve_enabled = true
  },
]

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
traffic_manager_dns_name = null
dns_ttl                  = 60
traffic_routing_method   = "Priority"
monitor_protocol         = "HTTPS"
monitor_port             = 443
monitor_path             = "/"
tags                     = {}

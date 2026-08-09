deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "traffic-manager-example"
environment                = "prod"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "traffic-manager-example"
environment_tag     = "Production"
owner               = "CloudEngineering"
cost_center         = "traffic-manager-example"
criticality         = "High"
service             = "EntryPoint"
data_classification = "Confidential"
lifecycle_stage     = "Permanent"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

# Performance routing sends each client to the region closest to it, so
# every endpoint names the region it sits in. Priority routing is the
# alternative when one region is primary and the others stand by.
traffic_routing_method = "Performance"

# Dummy endpoints, served without probing so the profile answers
# queries before any real target exists. Replace the targets with the
# regional deployments' hostnames and turn always_serve_enabled off:
# without probing, Traffic Manager keeps sending clients to a region
# that has stopped answering.
external_endpoints = [
  {
    name                 = "uksouth"
    target               = "placeholder-uksouth.example.com"
    location             = "uksouth"
    priority             = 1
    weight               = 100
    always_serve_enabled = true
  },
  {
    name                 = "ukwest"
    target               = "placeholder-ukwest.example.com"
    location             = "ukwest"
    priority             = 2
    weight               = 100
    always_serve_enabled = true
  },
]

monitor_path = "/healthz"

# A shorter TTL fails clients over sooner once an endpoint is taken out
# of rotation, at the cost of more queries.
dns_ttl = 30

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
traffic_manager_dns_name = null
monitor_protocol         = "HTTPS"
monitor_port             = 443
tags                     = {}

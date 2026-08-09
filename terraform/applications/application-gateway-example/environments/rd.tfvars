deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "app-gateway-example"
environment                = "rd"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "app-gateway-example"
environment_tag     = "RD"
owner               = "CloudEngineering"
cost_center         = "app-gateway-example"
criticality         = "Low"
service             = "EntryPoint"
data_classification = "Internal"
lifecycle_stage     = "Sandbox"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

application_gateway_sku = "Standard_v2"

# Dummy backend: the gateway deploys complete and reports the backend
# unhealthy until this hostname points at something real.
backend_fqdns = ["placeholder-backend.example.com"]

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
address_space                          = "10.250.0.0/24"
application_gateway_subnet_name        = "snet-application-gateway"
application_gateway_subnet_prefix      = "10.250.0.0/27"
application_gateway_private_ip_address = null
application_gateway_waf_mode           = "Prevention"
application_gateway_min_capacity       = 1
application_gateway_max_capacity       = 2
application_gateway_zones              = null
backend_ip_addresses                   = []
backend_protocol                       = "Https"
backend_port                           = 443
backend_host_name                      = null
backend_probe_path                     = "/"
backend_probe_protocol                 = null
ssl_certificate_key_vault_secret_id    = null
identity_ids                           = []
enable_diagnostics                     = false
monitoring_subscription_id             = null
monitoring_deployment_name             = "monitoring-spoke"
tags                                   = {}

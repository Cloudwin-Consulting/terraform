deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "app-gateway-example"
environment                = "prod"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "app-gateway-example"
environment_tag     = "Production"
owner               = "CloudEngineering"
cost_center         = "app-gateway-example"
criticality         = "High"
service             = "EntryPoint"
data_classification = "Confidential"
lifecycle_stage     = "Permanent"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

# Production runs the firewall in blocking mode, scales out and spreads
# the gateway across the region's availability zones.
application_gateway_sku          = "WAF_v2"
application_gateway_waf_mode     = "Prevention"
application_gateway_min_capacity = 2
application_gateway_max_capacity = 10
application_gateway_zones        = ["1", "2", "3"]

# Dummy backend: the gateway deploys complete and reports the backend
# unhealthy until this hostname points at something real. A production
# listener should also terminate TLS - set
# ssl_certificate_key_vault_secret_id and identity_ids together.
backend_fqdns = ["placeholder-backend.example.com"]

enable_diagnostics         = true
monitoring_deployment_name = "monitoring-spoke"

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
address_space                          = "10.250.0.0/24"
application_gateway_subnet_name        = "snet-application-gateway"
application_gateway_subnet_prefix      = "10.250.0.0/27"
application_gateway_private_ip_address = null
backend_ip_addresses                   = []
backend_protocol                       = "Https"
backend_port                           = 443
backend_host_name                      = null
backend_probe_path                     = "/"
backend_probe_protocol                 = null
ssl_certificate_key_vault_secret_id    = null
identity_ids                           = []
monitoring_subscription_id             = null
tags                                   = {}

deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "jumpbox"
environment                = "rd"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "jumpbox"
environment_tag     = "RD"
owner               = "CloudEngineering"
cost_center         = "jumpbox"
criticality         = "Low"
service             = "Management"
data_classification = "Internal"
lifecycle_stage     = "Sandbox"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

hub_subscription_id = null
hub_deployment_name = "hub-spoke"

# Pre-load the jump box SSH public key into the hub's platform key
# vault (Secrets Officer, from inside the network) before deploying.
admin_ssh_public_key_key_vault_secret = {
  secret_name = "jumpbox-admin-ssh-public-key"
}

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
hub_shared_subnet_name             = "snet-hub-shared"
virtual_machine_size               = "Standard_B2s"
platform_key_vault_subscription_id = null
tags                               = {}

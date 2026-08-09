deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "golden-image"
environment                = "rd"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "golden-image"
environment_tag     = "RD"
owner               = "CloudEngineering"
cost_center         = "golden-image"
criticality         = "Low"
service             = "Compute"
data_classification = "Internal"
lifecycle_stage     = "Sandbox"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

app_spoke_subscription_id = null
app_spoke_deployment_name = "app-spoke"

# Pre-load the builder's SSH public key into the spoke's platform key
# vault (Secrets Officer, from inside the network) before deploying.
admin_ssh_public_key_key_vault_secret = {
  secret_name = "golden-image-builder-ssh-public-key"
}

application_security_group_role = "linux-vm"

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
virtual_machine_subnet_name        = "snet-linux-vm"
gallery_name                       = null
image_publisher                    = "cloudwin"
builder_size                       = "Standard_D2s_v5"
platform_key_vault_subscription_id = null
tags                               = {}

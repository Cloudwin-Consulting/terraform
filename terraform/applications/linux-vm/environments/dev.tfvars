deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "linux-vm"
environment                = "dev"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "linux-vm"
environment_tag     = "Development"
owner               = "CloudEngineering"
cost_center         = "linux-vm"
criticality         = "Low"
service             = "Compute"
data_classification = "Internal"
lifecycle_stage     = "Temporary"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

app_spoke_subscription_id       = null
app_spoke_deployment_name       = "app-spoke"
application_security_group_role = "linux-vm"

hub_subscription_id = null
hub_deployment_name = "hub-spoke"

monitoring_subscription_id = null
monitoring_deployment_name = "monitoring-spoke"

# Pre-load the admin SSH public key into the spoke's platform key
# vault (Secrets Officer, from inside the network) before deploying.
admin_ssh_public_key_key_vault_secret = {
  secret_name = "linux-vm-admin-ssh-public-key"
}

virtual_machine_size = "Standard_B2s"

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
virtual_machine_subnet_name           = "snet-linux-vm"
private_endpoint_subnet_name          = "snet-private-endpoints"
virtual_machine_count                 = 1
availability_zones                    = []
os_disk                               = {}
data_disks                            = []
source_image_id                       = null
enable_backup                         = false
backup_private_endpoint_dns_zone_name = null
backup_daily_retention_days           = 7
enable_monitor_agent                  = false
data_collection_endpoint_name         = null
enable_load_balancer                  = false
load_balancer_rules = [
  {
    name          = "https"
    frontend_port = 443
    backend_port  = 443
  }
]
secure_boot_enabled                     = true
vtpm_enabled                            = true
encryption_at_host_enabled              = true
key_vault_name                          = null
key_vault_secrets_officer_principal_ids = []
platform_key_vault_subscription_id      = null
tags                                    = {}

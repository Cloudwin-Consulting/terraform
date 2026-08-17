deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "linux-vm"
environment                = "prod"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "linux-vm"
environment_tag     = "Production"
owner               = "CloudEngineering"
cost_center         = "linux-vm"
criticality         = "High"
service             = "Compute"
data_classification = "Confidential"
lifecycle_stage     = "Permanent"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

app_spoke_subscription_id       = null
app_spoke_deployment_name       = "app-spoke"
application_security_group_role = "linux-vm"

hub_subscription_id = null
hub_deployment_name = "hub-spoke"

monitoring_subscription_id    = null
monitoring_deployment_name    = "monitoring-spoke"
data_collection_endpoint_name = null

# Pre-load the admin SSH public key into the spoke's platform key
# vault (Secrets Officer, from inside the network) before deploying.
admin_ssh_public_key_key_vault_secret = {
  secret_name = "linux-vm-admin-ssh-public-key"
}

virtual_machine_size = "Standard_D2s_v5"

# Production scales out across availability zones behind the internal
# load balancer; the other environments run a single regional machine.
virtual_machine_count = 3
availability_zones    = ["1", "2", "3"]
enable_load_balancer  = true

# Production machines are backed up daily, monitored through the Azure
# Monitor Agent, and carry a premium data disk each.
enable_backup                         = true
backup_private_endpoint_dns_zone_name = "privatelink.uks.backup.windowsazure.com"
backup_daily_retention_days           = 30
enable_monitor_agent                  = true

data_disks = [
  {
    name                 = "data"
    disk_size_gb         = 128
    lun                  = 1
    storage_account_type = "Premium_LRS"
  }
]

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
virtual_machine_subnet_name  = "snet-linux-vm"
private_endpoint_subnet_name = "snet-private-endpoints"
os_disk                      = {}
source_image_id              = null
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

deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "monitoring-spoke"
environment                = "qa"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "monitoring-spoke"
environment_tag     = "QA"
owner               = "PlatformEngineering"
cost_center         = "Platform"
criticality         = "Medium"
service             = "Monitoring"
data_classification = "Internal"
lifecycle_stage     = "Temporary"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

hub_subscription_id = null
hub_deployment_name = "hub-spoke"

# Everything beyond the virtual network is opt-in. The worked example
# enables the full monitoring stack.
enable_hub_peering          = true
enable_hub_dns_zone_links   = true
enable_log_analytics        = true
enable_application_insights = true
enable_log_archive_storage  = true

# Platform key vault in a dedicated resource group; administrators
# pre-load secrets for other deployments here.
enable_platform_key_vault = true

# Hub peering is not transitive: peer directly with the application
# spoke so its workloads reach the private ingestion endpoint. Deploy
# the application spoke first.
enable_application_spoke_peering  = true
application_spoke_subscription_id = null
application_spoke_deployment_name = "app-spoke"

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
enable_virtual_network         = true
address_space                  = ["10.240.8.0/22"]
private_endpoint_subnet_name   = "snet-private-endpoints"
private_endpoint_subnet_prefix = "10.240.8.0/24"
use_hub_gateway                = false
hub_private_dns_zone_names = [
  "privatelink.azurewebsites.net",
  "privatelink.blob.core.windows.net",
  "privatelink.monitor.azure.com",
  "privatelink.oms.opinsights.azure.com",
  "privatelink.ods.opinsights.azure.com",
  "privatelink.agentsvc.azure-automation.net",
]
ampls_private_dns_zone_names = [
  "privatelink.monitor.azure.com",
  "privatelink.oms.opinsights.azure.com",
  "privatelink.ods.opinsights.azure.com",
  "privatelink.agentsvc.azure-automation.net",
  "privatelink.blob.core.windows.net",
]
log_retention_in_days                            = 30
storage_account_name                             = null
log_archive_table_names                          = ["AzureActivity", "Heartbeat", "Perf", "Syslog", "Event"]
log_archive_replication_type                     = "GZRS"
log_archive_public_network_access_enabled        = false
log_archive_shared_access_key_enabled            = false
log_archive_customer_managed_key                 = null
platform_key_vault_name                          = null
platform_key_vault_secrets_officer_principal_ids = []
tags                                             = {}

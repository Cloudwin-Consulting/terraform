deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "hub-spoke"
environment                = "prod"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "hub-spoke"
environment_tag     = "Production"
owner               = "PlatformEngineering"
cost_center         = "Platform"
criticality         = "Critical"
service             = "Networking"
data_classification = "Confidential"
lifecycle_stage     = "Permanent"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

# Everything beyond the virtual network is opt-in. The worked example
# enables the management entry point and the private endpoint DNS
# zones; the firewall, DNS resolver and VPN gateway stay off.
enable_bastion           = true
bastion_sku              = "Developer"
enable_private_dns_zones = true

# Platform key vault in a dedicated resource group; administrators
# pre-load secrets for other deployments here.
enable_platform_key_vault = true

# Geo-specific zone for Recovery Services vault private endpoints,
# used by the production VM workloads' backup vaults.
additional_private_dns_zone_names = ["privatelink.uks.backup.windowsazure.com"]

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
enable_virtual_network             = true
address_space                      = ["10.240.0.0/22"]
gateway_subnet_prefix              = "10.240.0.0/27"
dns_resolver_inbound_subnet_prefix = "10.240.0.32/28"
firewall_subnet_prefix             = "10.240.0.64/26"
bastion_subnet_prefix              = "10.240.0.128/26"
shared_subnet_prefix               = "10.240.1.0/24"
private_dns_zone_names = [
  "privatelink.azurewebsites.net",
  "privatelink.blob.core.windows.net",
  "privatelink.file.core.windows.net",
  "privatelink.queue.core.windows.net",
  "privatelink.table.core.windows.net",
  "privatelink.vaultcore.azure.net",
  "privatelink.azurecr.io",
  "privatelink.servicebus.windows.net",
  "privatelink.database.windows.net",
  "privatelink.postgres.database.azure.com",
  "privatelink.mysql.database.azure.com",
  "privatelink.redis.cache.windows.net",
  "privatelink.azconfig.io",
  "privatelink.documents.azure.com",
  "privatelink.monitor.azure.com",
  "privatelink.oms.opinsights.azure.com",
  "privatelink.ods.opinsights.azure.com",
  "privatelink.agentsvc.azure-automation.net",
]
enable_firewall                   = false
firewall_sku_tier                 = "Standard"
firewall_threat_intelligence_mode = "Deny"
firewall_idps_mode                = "Deny"
firewall_dns_proxy_enabled        = false
firewall_dns_servers              = []
firewall_zones                    = null
firewall_rule_collection_groups = {
  platform-baseline = {
    priority = 300

    # DNAT first: publish the application gateway's private frontend
    # on the firewall's public IP (destination_address null = the
    # firewall's own public IP).
    nat_rule_collections = [
      {
        name     = "inbound-dnat"
        priority = 100
        rules = [
          # The worked application gateway listens on HTTP 80 (the
          # spoke passes it no TLS certificate); publish that
          # listener as-is, and switch this rule to 443 once the
          # gateway terminates TLS with a key vault certificate.
          # translated_address must equal the spoke's
          # application_gateway_private_ip_address output - the hub
          # deploys first, so nothing checks it at plan time.
          {
            name               = "http-to-app-gateway"
            protocols          = ["TCP"]
            source_addresses   = ["*"]
            destination_ports  = ["80"]
            translated_address = "10.240.7.42"
            translated_port    = 80
          }
        ]
      }
    ]

    # Outbound network rules for the platform dependencies every
    # spoke workload needs.
    network_rule_collections = [
      {
        name     = "allow-outbound-platform"
        priority = 200
        action   = "Allow"
        rules = [
          {
            name                  = "dns-to-azure"
            protocols             = ["TCP", "UDP"]
            source_addresses      = ["10.240.0.0/16"]
            destination_addresses = ["168.63.129.16"]
            destination_ports     = ["53"]
          },
          {
            name                  = "ntp"
            protocols             = ["UDP"]
            source_addresses      = ["10.240.0.0/16"]
            destination_addresses = ["*"]
            destination_ports     = ["123"]
          },
          {
            name                  = "entra-id"
            protocols             = ["TCP"]
            source_addresses      = ["10.240.0.0/16"]
            destination_addresses = ["AzureActiveDirectory"]
            destination_ports     = ["443"]
          },
          {
            name                  = "azure-monitor"
            protocols             = ["TCP"]
            source_addresses      = ["10.240.0.0/16"]
            destination_addresses = ["AzureMonitor"]
            destination_ports     = ["443"]
          }
        ]
      }
    ]

    # Outbound application rules for OS updates and source control.
    application_rule_collections = [
      {
        name     = "allow-outbound-web"
        priority = 400
        action   = "Allow"
        rules = [
          {
            name                  = "windows-update"
            source_addresses      = ["10.240.0.0/16"]
            destination_fqdn_tags = ["WindowsUpdate"]
            protocols = [
              { type = "Http", port = 80 },
              { type = "Https", port = 443 }
            ]
          },
          {
            name             = "ubuntu-packages"
            source_addresses = ["10.240.0.0/16"]
            destination_fqdns = [
              "archive.ubuntu.com",
              "security.ubuntu.com",
              "azure.archive.ubuntu.com"
            ]
            protocols = [
              { type = "Http", port = 80 },
              { type = "Https", port = 443 }
            ]
          },
          {
            name             = "github"
            source_addresses = ["10.240.0.0/16"]
            destination_fqdns = [
              "github.com",
              "*.github.com",
              "*.githubusercontent.com"
            ]
            protocols = [
              { type = "Https", port = 443 }
            ]
          }
        ]
      }
    ]
  }
}
enable_dns_resolver                              = false
enable_vpn_gateway                               = false
vpn_gateway_sku                                  = "VpnGw1"
platform_key_vault_name                          = null
platform_key_vault_secrets_officer_principal_ids = []
vpn_gateway_zones                                = null
enable_monitor_alerts                            = false
monitor_action_group_short_name                  = "hub-ops"
monitor_alert_email_receivers                    = {}
tags                                             = {}

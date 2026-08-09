deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "app-spoke"
environment                = "qa"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "app-spoke"
environment_tag     = "QA"
owner               = "PlatformEngineering"
cost_center         = "Platform"
criticality         = "Medium"
service             = "Networking"
data_classification = "Internal"
lifecycle_stage     = "Temporary"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

hub_subscription_id = null
hub_deployment_name = "hub-spoke"

# Everything beyond the virtual network is opt-in. The worked example
# connects the spoke to the hub; API Management stays off.
enable_hub_peering        = true
enable_hub_dns_zone_links = true

# Platform key vault in a dedicated resource group; administrators
# pre-load secrets for other deployments here.
enable_platform_key_vault = true

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
enable_virtual_network = true
address_space          = ["10.240.4.0/22"]
subnets = {
  "snet-app1-integration" = {
    address_prefixes = ["10.240.4.0/26"]
    delegation = {
      name         = "appservice"
      service_name = "Microsoft.Web/serverFarms"
    }
  }
  "snet-app2-integration" = {
    address_prefixes = ["10.240.4.64/26"]
    delegation = {
      name         = "appservice"
      service_name = "Microsoft.Web/serverFarms"
    }
  }
  "snet-func-integration" = {
    address_prefixes = ["10.240.4.128/26"]
    delegation = {
      name         = "appservice"
      service_name = "Microsoft.Web/serverFarms"
    }
  }
  "snet-logic-integration" = {
    address_prefixes = ["10.240.4.192/26"]
    delegation = {
      name         = "appservice"
      service_name = "Microsoft.Web/serverFarms"
    }
  }
  "snet-private-endpoints" = {
    address_prefixes = ["10.240.5.0/24"]
  }
  "snet-linux-vm" = {
    address_prefixes = ["10.240.6.0/26"]
  }
  "snet-windows-vm" = {
    address_prefixes = ["10.240.6.64/26"]
  }
  "snet-container-apps" = {
    address_prefixes = ["10.240.6.128/27"]
    delegation = {
      name         = "containerapps"
      service_name = "Microsoft.App/environments"
      actions      = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
  "snet-aks" = {
    address_prefixes = ["10.240.6.160/27"]
  }
  "snet-api-management" = {
    address_prefixes = ["10.240.7.0/27"]
  }
  "snet-app-gateway" = {
    address_prefixes = ["10.240.7.32/27"]
  }
  "snet-eventpipe-integration" = {
    address_prefixes = ["10.240.6.192/26"]
    delegation = {
      name         = "appservice"
      service_name = "Microsoft.Web/serverFarms"
    }
  }
  "snet-api-integration" = {
    address_prefixes = ["10.240.7.64/26"]
    delegation = {
      name         = "appservice"
      service_name = "Microsoft.Web/serverFarms"
    }
  }
  "snet-cms-integration" = {
    address_prefixes = ["10.240.7.128/26"]
    delegation = {
      name         = "appservice"
      service_name = "Microsoft.Web/serverFarms"
    }
  }
  "snet-postgresql" = {
    address_prefixes = ["10.240.7.192/28"]
    delegation = {
      name         = "postgresql"
      service_name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions      = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
  "snet-mysql" = {
    address_prefixes = ["10.240.7.208/28"]
    delegation = {
      name         = "mysql"
      service_name = "Microsoft.DBforMySQL/flexibleServers"
      actions      = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
  "snet-private-link-service" = {
    address_prefixes                              = ["10.240.7.224/28"]
    private_link_service_network_policies_enabled = false
  }
}
private_endpoint_subnet_name = "snet-private-endpoints"
virtual_machine_subnet_names = ["snet-linux-vm", "snet-windows-vm"]
container_apps_subnet_name   = "snet-container-apps"
aks_subnet_name              = "snet-aks"
aks_pod_cidr                 = "10.244.0.0/16"
# The address the cluster's internal load balancer frontend takes, so
# the application gateway can point its backend pool at it. The last
# usable address of the AKS subnet, well clear of the node addresses
# Azure allocates from the low end. Must equal the aks stack's
# store_front_load_balancer_ip.
aks_ingress_ip_address           = "10.240.6.190"
api_management_subnet_name       = "snet-api-management"
application_gateway_subnet_name  = "snet-app-gateway"
enable_nat_gateway               = false
nat_gateway_zone                 = null
database_subnet_names            = ["snet-postgresql", "snet-mysql"]
private_link_service_subnet_name = "snet-private-link-service"
virtual_machine_workload_inbound_rules = [
  {
    name        = "https"
    port_ranges = ["443"]
  }
]
active_directory_outbound_address_prefixes = []
bastion_source_address_prefix              = "10.240.0.128/26"
use_hub_gateway                            = false
hub_private_dns_zone_names = [
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
dns_servers                                      = []
additional_hub_private_dns_zone_names            = []
enable_api_management                            = false
api_management_name                              = null
api_management_publisher_name                    = null
api_management_publisher_email                   = null
api_management_sku                               = "Developer_1"
enable_front_door                                = false
front_door_name                                  = null
front_door_sku                                   = "Premium_AzureFrontDoor"
enable_application_gateway                       = false
application_gateway_sku                          = "Standard_v2"
application_gateway_backend_fqdns                = []
application_gateway_backend_ip_addresses         = []
application_gateway_backend_protocol             = "Https"
application_gateway_backend_port                 = 443
application_gateway_backend_probe_path           = "/"
application_gateway_zones                        = null
platform_key_vault_name                          = null
platform_key_vault_secrets_officer_principal_ids = []
tags                                             = {}

variable "deployment_subscription_id" {
  description = "The Azure subscription into which resources will be deployed."
  type        = string
}

variable "deployment_location" {
  description = "The Azure location into which resources will be deployed."
  type        = string
}

variable "deployment_name" {
  description = "The name of the workload being deployed, without the environment (e.g. app-spoke). Every resource name is derived from it and environment together - rg-<deployment_name>-<environment> for the core resource group, rg-<deployment_name>-<environment>-network, -dns and -secrets for the network, DNS and secrets groups, and <abbreviation>-<deployment_name>-<environment> for the resources in them - so the pair must be unique across all stacks and environments: a workload name reused in the same environment derives the same resource group name and clashes on globally unique names. Downstream stacks rebuild this spoke's names the same way, so their app_spoke_deployment_name must match this value and they must deploy into the same environment."
  type        = string
}

variable "environment" {
  description = "The environment this deployment targets (e.g. rd, dev, qa, prod). It is appended to deployment_name to derive every resource name, and to the upstream workload names this stack looks its dependencies up by, so a single configuration targets any environment by changing this value alone."
  type        = string
}

variable "enable_virtual_network" {
  description = "Whether to deploy the application spoke virtual network and its network security groups. Every other component requires it."
  type        = bool
  default     = true
}

variable "address_space" {
  description = "The address space of the application spoke virtual network."
  type        = list(string)
  default     = ["10.240.4.0/22"]
}

variable "subnets" {
  description = "Subnets created in the application spoke, keyed by subnet name."
  type = map(object({
    address_prefixes                              = list(string)
    service_endpoints                             = optional(list(string), [])
    private_endpoint_network_policies             = optional(string, "Enabled")
    private_link_service_network_policies_enabled = optional(bool, true)
    delegation = optional(object({
      name         = string
      service_name = string
      actions      = optional(list(string), ["Microsoft.Network/virtualNetworks/subnets/action"])
    }), null)
  }))
  default = {
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
    # The NAT addresses a private link service translates connections
    # through, e.g. the one publishing the AKS cluster's internal load
    # balancer to Front Door. The service cannot take addresses from a
    # subnet that still enforces network policies on them.
    "snet-private-link-service" = {
      address_prefixes                              = ["10.240.7.224/28"]
      private_link_service_network_policies_enabled = false
    }
  }
}

variable "private_endpoint_subnet_name" {
  description = "The name of the subnet that hosts private endpoints. Must be a key of the subnets variable."
  type        = string
  default     = "snet-private-endpoints"
}

variable "virtual_machine_subnet_names" {
  description = "The names of the subnets that host virtual machines. Must be keys of the subnets variable."
  type        = list(string)
  default     = ["snet-linux-vm", "snet-windows-vm"]
}

variable "container_apps_subnet_name" {
  description = "The name of the delegated container apps infrastructure subnet. Must be a key of the subnets variable."
  type        = string
  default     = "snet-container-apps"
}

variable "aks_subnet_name" {
  description = "The name of the subnet that hosts the AKS cluster's nodes and internal load balancer frontends. Must be a key of the subnets variable."
  type        = string
  default     = "snet-aks"

  validation {
    condition     = contains(keys(var.subnets), var.aks_subnet_name)
    error_message = "aks_subnet_name must be a key of the subnets variable."
  }
}

variable "private_link_service_subnet_name" {
  description = "The name of the subnet a private link service draws its NAT addresses from - e.g. the aks stack's, publishing the cluster's internal load balancer to Front Door. Must be a key of the subnets variable, and that subnet must set private_link_service_network_policies_enabled = false."
  type        = string
  default     = "snet-private-link-service"

  validation {
    condition     = contains(keys(var.subnets), var.private_link_service_subnet_name)
    error_message = "private_link_service_subnet_name must be a key of the subnets variable."
  }

  validation {
    condition     = !contains(keys(var.subnets), var.private_link_service_subnet_name) || var.subnets[var.private_link_service_subnet_name].private_link_service_network_policies_enabled == false
    error_message = "The private link service subnet must set private_link_service_network_policies_enabled = false: a private link service cannot take NAT addresses from a subnet that still enforces those policies."
  }
}

variable "aks_pod_cidr" {
  description = "The overlay address range the AKS cluster's pods draw their addresses from - the aks stack's pod_cidr, which must match this value exactly. With Azure CNI overlay, cross-node pod traffic travels the node subnet carrying these addresses, so the AKS subnet NSG allows cluster-internal traffic between this range and the node subnet. Must not overlap the network's routed ranges."
  type        = string
  default     = "10.244.0.0/16"

  validation {
    condition     = can(cidrhost(var.aks_pod_cidr, 0))
    error_message = "aks_pod_cidr must be a valid CIDR range, e.g. 10.244.0.0/16."
  }

  validation {
    # Two CIDR ranges overlap exactly when they share the same network
    # address at the shorter of the two prefix lengths. The overlay
    # range must stay outside the spoke's address space, which contains
    # every subnet including the AKS node subnet.
    condition = !can(cidrhost(var.aks_pod_cidr, 0)) || alltrue([
      for prefix in var.address_space :
      cidrhost(format("%s/%d", split("/", prefix)[0], min(tonumber(split("/", prefix)[1]), tonumber(split("/", var.aks_pod_cidr)[1]))), 0) !=
      cidrhost(format("%s/%d", split("/", var.aks_pod_cidr)[0], min(tonumber(split("/", prefix)[1]), tonumber(split("/", var.aks_pod_cidr)[1]))), 0)
    ])
    error_message = "aks_pod_cidr must not overlap the spoke's address_space (which contains the AKS node subnet): the overlay range is separate from the network's routed ranges."
  }
}

variable "aks_ingress_ip_address" {
  description = "The address the AKS cluster's internal load balancer frontend takes in the AKS subnet - the aks stack's store_front_load_balancer_ip, which must match this value exactly. Pinning it lets this spoke point the application gateway's backend pool at the cluster, which deploys after it. Leave null to let the cluster take any free address, in which case nothing here can reference it."
  type        = string
  default     = null

  validation {
    condition     = var.aks_ingress_ip_address == null || can(cidrhost("${var.aks_ingress_ip_address}/32", 0))
    error_message = "aks_ingress_ip_address must be a valid IP address, e.g. 10.240.6.185."
  }

  validation {
    # An address sits inside a prefix when the two share a network
    # address at the prefix's length - and has to be one Azure will
    # hand out, which rules out the four addresses it reserves at the
    # start of every subnet and the one at the end.
    #
    # The null opt-out is a conditional rather than the left side of an
    # ||: Terraform evaluates both operands of ||, so the address
    # arithmetic would still run against null and fail the plan for the
    # very configurations the default is meant to leave alone. try()
    # then makes a malformed address "no match" instead of an error, so
    # it reaches the message below rather than a stack trace.
    condition = var.aks_ingress_ip_address == null || !contains(keys(var.subnets), var.aks_subnet_name) ? true : anytrue([
      for prefix in var.subnets[var.aks_subnet_name].address_prefixes : try(
        cidrhost("${var.aks_ingress_ip_address}/${split("/", prefix)[1]}", 0) == cidrhost(prefix, 0)
        && !contains([
          cidrhost(prefix, 0),
          cidrhost(prefix, 1),
          cidrhost(prefix, 2),
          cidrhost(prefix, 3),
          cidrhost(prefix, -1),
        ], var.aks_ingress_ip_address),
        false
      )
    ])
    error_message = "aks_ingress_ip_address must be a usable address of the AKS subnet: the cluster's internal load balancer frontend takes its address from that subnet, and Azure reserves the first four addresses and the last of every subnet."
  }
}

variable "api_management_subnet_name" {
  description = "The name of the subnet that hosts API Management. Must be a key of the subnets variable."
  type        = string
  default     = "snet-api-management"
}

variable "application_gateway_subnet_name" {
  description = "The name of the dedicated application gateway subnet. Must be a key of the subnets variable."
  type        = string
  default     = "snet-app-gateway"
}

variable "enable_nat_gateway" {
  description = "Whether to give the virtual machine subnets an explicit outbound path through a NAT gateway. Standard internal load balancers provide no outbound connectivity, so enable this wherever load-balanced machines reach the internet - unless route tables send their egress through the hub firewall instead."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_nat_gateway || var.enable_virtual_network
    error_message = "enable_nat_gateway requires enable_virtual_network."
  }
}

variable "nat_gateway_zone" {
  description = "The availability zone of the NAT gateway, e.g. \"1\". NAT gateways are zonal; leave null for a non-zonal deployment."
  type        = string
  default     = null
}

variable "database_subnet_names" {
  description = "Names of the subnets delegated to database flexible servers. Excluded from App Service integration handling and covered by the database NSG."
  type        = list(string)
  default     = ["snet-postgresql", "snet-mysql"]
}

variable "virtual_machine_workload_inbound_rules" {
  description = "Workload traffic allowed into the virtual machine subnets, matched against the machines' ASGs. Align these with the ports and protocols the VM stacks' load_balancer_rules expose - the subnet NSG denies anything not listed here. source_address_prefix defaults to the hub and spoke network; widen it to Internet only for a workload published through a load balancer with public_ip_enabled."
  type = list(object({
    name                  = string
    protocol              = optional(string, "Tcp")
    port_ranges           = list(string)
    source_address_prefix = optional(string, "VirtualNetwork")
  }))
  default = [
    {
      name        = "https"
      port_ranges = ["443"]
    }
  ]

  validation {
    condition     = alltrue([for rule in var.virtual_machine_workload_inbound_rules : contains(["Tcp", "Udp", "*"], rule.protocol) && can(regex("^[a-zA-Z0-9-]{1,50}$", rule.name)) && length(rule.port_ranges) > 0])
    error_message = "Workload inbound rules need a protocol of Tcp, Udp or *, at least one port range and a name of up to 50 letters, numbers and hyphens - the name is embedded in the generated NSG rule name and description, which Azure caps at 80 and 140 characters."
  }
}

variable "active_directory_outbound_address_prefixes" {
  description = "Address prefixes of the Active Directory domain controllers that domain-joined machines need to reach, e.g. on-premises ranges or an identity subnet. When set, the VM subnet NSG allows Kerberos, LDAP(S), SMB, RPC and related traffic from the Windows ASG to these prefixes. Leave empty when nothing is domain joined."
  type        = list(string)
  default     = []
}

variable "bastion_source_address_prefix" {
  description = "The address prefix of the hub's Azure Bastion subnet, allowed to open SSH and RDP sessions to virtual machines."
  type        = string
  default     = "10.240.0.128/26"
}

variable "enable_hub_peering" {
  description = "Whether to peer the spoke with the hub virtual network."
  type        = bool
  default     = false
}

variable "use_hub_gateway" {
  description = "Whether spoke traffic can use the hub's VPN or ExpressRoute gateway through the peering. Requires the hub gateway to be deployed first."
  type        = bool
  default     = false
}

variable "enable_hub_dns_zone_links" {
  description = "Whether to link the spoke to the hub's private DNS zones. Requires the hub to have its private DNS zones enabled."
  type        = bool
  default     = false
}

variable "hub_subscription_id" {
  description = "The Azure subscription the hub is deployed into, when it differs from this deployment's subscription. Leave null when hub and spoke share a subscription. The deployment identity must be able to read the hub's virtual network and private DNS zones and to create peerings and DNS zone links there."
  type        = string
  default     = null
}

variable "hub_deployment_name" {
  description = "The workload name of the hub this stack looks up, without the environment (e.g. hub-spoke). Its network and DNS resource groups are looked up as rg-<hub_deployment_name>-<environment>-network and rg-<hub_deployment_name>-<environment>-dns, and its virtual network as vnet-<hub_deployment_name>-<environment>, so it must match the hub stack's deployment_name and the hub must be deployed into the same environment."
  type        = string
  default     = "hub-spoke"
}

variable "hub_private_dns_zone_names" {
  description = "Private DNS zones in the hub to link this spoke to."
  type        = list(string)
  default = [
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
}

variable "dns_servers" {
  description = "Custom DNS servers of the spoke virtual network, e.g. Active Directory domain controllers (required for the windows-vm stack's domain join) or the hub's DNS resolver inbound endpoint. Leave empty for Azure-provided DNS."
  type        = list(string)
  default     = []
}

variable "additional_hub_private_dns_zone_names" {
  description = "Extra hub private DNS zones to link this spoke to, e.g. the geo-specific privatelink.<geo>.backup.windowsazure.com zone when workloads use Recovery Services vault private endpoints."
  type        = list(string)
  default     = []
}

variable "enable_api_management" {
  description = "Whether to deploy an internal API Management instance into the spoke. Deployment takes 30 minutes or more."
  type        = bool
  default     = false
}

variable "api_management_name" {
  description = "The globally unique name of the API Management instance. Defaults to apim-<deployment_name>-<environment>."
  type        = string
  default     = null
}

variable "api_management_publisher_name" {
  description = "The name of the API publisher organisation. Required when API Management is enabled."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_api_management || var.api_management_publisher_name != null
    error_message = "api_management_publisher_name must be set when enable_api_management is true."
  }
}

variable "api_management_publisher_email" {
  description = "The email address of the API publisher. Required when API Management is enabled."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_api_management || var.api_management_publisher_email != null
    error_message = "api_management_publisher_email must be set when enable_api_management is true."
  }
}

variable "api_management_sku" {
  description = "The SKU of the API Management instance including capacity. Only Developer and Premium support virtual network injection."
  type        = string
  default     = "Developer_1"
}

variable "enable_front_door" {
  description = "Whether to deploy a Front Door profile. Applications add their own endpoints to it with the front-door-endpoint module."
  type        = bool
  default     = false
}

variable "front_door_name" {
  description = "The name of the Front Door profile. Defaults to afd-<deployment_name>-<environment>."
  type        = string
  default     = null
}

variable "front_door_sku" {
  description = "The SKU of the Front Door profile. Premium_AzureFrontDoor is required for private link origins."
  type        = string
  default     = "Premium_AzureFrontDoor"
}

variable "enable_application_gateway" {
  description = "Whether to deploy an internal-listener application gateway into the dedicated subnet."
  type        = bool
  default     = false
}

variable "application_gateway_sku" {
  description = "The SKU (name and tier) of the application gateway: Standard_v2 or WAF_v2."
  type        = string
  default     = "Standard_v2"
}

variable "application_gateway_backend_fqdns" {
  description = "Hostnames of the application gateway's backend pool members, e.g. web app default hostnames. Mutually exclusive with application_gateway_backend_ip_addresses."
  type        = list(string)
  default     = []
}

variable "application_gateway_backend_ip_addresses" {
  description = "Addresses of the application gateway's backend pool members, for backends with no hostname of their own. Set this to aks_ingress_ip_address to publish the AKS cluster's internal load balancer frontend through the gateway. Mutually exclusive with application_gateway_backend_fqdns."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.application_gateway_backend_fqdns) == 0 || length(var.application_gateway_backend_ip_addresses) == 0
    error_message = "The gateway's backend pool takes either application_gateway_backend_fqdns or application_gateway_backend_ip_addresses, not both."
  }
}

variable "application_gateway_backend_protocol" {
  description = "The protocol the gateway speaks to its backends: Http or Https. The AKS store front terminates no TLS of its own, so publishing it needs Http."
  type        = string
  default     = "Https"
}

variable "application_gateway_backend_port" {
  description = "The port the gateway connects to on its backends. The AKS store front's internal load balancer listens on 80."
  type        = number
  default     = 443
}

variable "application_gateway_backend_probe_path" {
  description = "The path the gateway probes to assess backend health. The AKS store front serves /health."
  type        = string
  default     = "/"
}

variable "application_gateway_zones" {
  description = "Availability zones of the application gateway, e.g. [\"1\", \"2\", \"3\"] for zone redundancy. Leave null for a regional deployment."
  type        = list(string)
  default     = null
}

variable "enable_platform_key_vault" {
  description = "Whether to deploy the spoke's platform key vault into the spoke's secrets resource group (rg-<deployment_name>-<environment>-secrets), for secrets that application deployments consume. Requires enable_virtual_network and the hub's private DNS zones."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_platform_key_vault || var.enable_virtual_network
    error_message = "enable_platform_key_vault requires enable_virtual_network: the vault is only reachable through its private endpoint."
  }

  validation {
    condition     = !var.enable_platform_key_vault || var.enable_hub_dns_zone_links
    error_message = "enable_platform_key_vault requires enable_hub_dns_zone_links: without the vault zone linked to this spoke's network, the vault hostname does not resolve to its private endpoint."
  }
}

variable "platform_key_vault_name" {
  description = "The globally unique name of the platform key vault. Defaults to kv-<deployment_name>-<environment>, which must stay within the 24 character vault name limit; it deploys into the dedicated rg-<deployment_name>-<environment>-secrets resource group."
  type        = string
  default     = null
}

variable "platform_key_vault_secrets_officer_principal_ids" {
  description = "Principal IDs granted the Key Vault Secrets Officer role on the platform key vault to pre-load secrets from inside the network, e.g. an administrators group object ID."
  type        = list(string)
  default     = []
}

# ------------------------------------------------------------
# Standard tags
#
# Every taggable resource this stack deploys carries the mandatory
# tag set - Application, Environment, Owner, CostCenter, ManagedBy
# and Criticality - plus the standard tags that apply to it. They are
# built once into local.common_tags and passed to every resource and
# every shared module, so tagging is configured here rather than
# resource by resource. The optional tags are only added once they
# have a value, so nothing carries an empty tag.
# ------------------------------------------------------------

variable "application" {
  description = "The value of the Application tag: the application or workload the resources belong to. Defaults to deployment_name."
  type        = string
  default     = null

  validation {
    condition     = var.application == null ? true : trimspace(var.application) != ""
    error_message = "application must not be empty. Leave it null to derive the Application tag from deployment_name."
  }
}

variable "environment_tag" {
  description = "The value of the Environment tag. Defaults to the standard name of the environment this stack deploys into (rd -> RD, dev -> Development, qa -> QA, prod -> Production); set it explicitly when environment holds a name outside that set. It is deliberately separate from environment, which stays the short form every resource name is derived from."
  type        = string
  default     = null

  validation {
    condition     = var.environment_tag == null ? true : contains(["RD", "Development", "QA", "Production"], var.environment_tag)
    error_message = "environment_tag must be one of: RD, Development, QA, Production."
  }

  validation {
    condition     = var.environment_tag != null || contains(["rd", "dev", "qa", "prod"], lower(var.environment))
    error_message = "environment_tag must be set explicitly when environment is not one of rd, dev, qa or prod."
  }
}

variable "owner" {
  description = "The value of the Owner tag: the team accountable for the workload."
  type        = string
  default     = "PlatformEngineering"

  validation {
    condition     = trimspace(var.owner) != ""
    error_message = "owner must not be empty: every resource carries an Owner tag."
  }
}

variable "cost_center" {
  description = "The value of the CostCenter tag: the cost centre this deployment's Azure spend is charged to. Defaults to the Application tag's value."
  type        = string
  default     = null

  validation {
    condition     = var.cost_center == null ? true : trimspace(var.cost_center) != ""
    error_message = "cost_center must not be empty. Leave it null to charge the spend to the Application tag's value."
  }
}

variable "criticality" {
  description = "The value of the Criticality tag: how business critical this deployment is."
  type        = string
  default     = "Medium"

  validation {
    condition     = contains(["Critical", "High", "Medium", "Low"], var.criticality)
    error_message = "criticality must be one of: Critical, High, Medium, Low."
  }
}

variable "service" {
  description = "The value of the Service tag: the service this deployment provides. One of Networking, Monitoring, ApplicationPlatform, Integration, Data, Compute, Management, EndUserComputing or EntryPoint."
  type        = string
  default     = "Networking"

  validation {
    condition     = contains(["Networking", "Monitoring", "ApplicationPlatform", "Integration", "Data", "Compute", "Management", "EndUserComputing", "EntryPoint"], var.service)
    error_message = "service must be one of: Networking, Monitoring, ApplicationPlatform, Integration, Data, Compute, Management, EndUserComputing, EntryPoint."
  }
}

variable "data_classification" {
  description = "The value of the DataClassification tag: the most sensitive data this deployment holds."
  type        = string
  default     = "Internal"

  validation {
    condition     = contains(["Public", "Internal", "Confidential", "Restricted"], var.data_classification)
    error_message = "data_classification must be one of: Public, Internal, Confidential, Restricted."
  }
}

variable "lifecycle_stage" {
  description = "The value of the Lifecycle tag: how long this deployment is expected to live. Named lifecycle_stage because Terraform reserves lifecycle as a variable name."
  type        = string
  default     = "Permanent"

  validation {
    condition     = contains(["Permanent", "Temporary", "Sandbox"], var.lifecycle_stage)
    error_message = "lifecycle_stage must be one of: Permanent, Temporary, Sandbox."
  }
}

variable "expiry_date" {
  description = "The value of the optional ExpiryDate tag, as YYYY-MM-DD: the date after which this deployment may be removed. Leave null on deployments that do not expire - the tag is then not applied at all rather than applied empty."
  type        = string
  default     = null

  validation {
    condition     = var.expiry_date == null ? true : can(formatdate("YYYY-MM-DD", "${var.expiry_date}T00:00:00Z"))
    error_message = "expiry_date must be a real calendar date in YYYY-MM-DD form, or null on deployments that do not expire."
  }
}

variable "business_unit" {
  description = "The value of the optional BusinessUnit tag: the part of the organisation the workload belongs to. Leave null to leave the tag off rather than applying it empty."
  type        = string
  default     = null

  validation {
    condition     = var.business_unit == null ? true : trimspace(var.business_unit) != ""
    error_message = "business_unit must not be empty. Leave it null to leave the BusinessUnit tag off."
  }
}

variable "repository" {
  description = "The value of the optional Repository tag: the source repository this deployment is applied from. Leave null to leave the tag off rather than applying it empty."
  type        = string
  default     = null

  validation {
    condition     = var.repository == null ? true : trimspace(var.repository) != ""
    error_message = "repository must not be empty. Leave it null to leave the Repository tag off."
  }
}

variable "tags" {
  description = "Additional tags applied to all resources in the deployment, merged over the standard tags."
  type        = map(string)
  default     = {}
}

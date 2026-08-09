locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  # The upstream stacks this one looks up derive their names the
  # same way, from their own workload name and this environment.
  hub_dns_resource_group_name     = "rg-${var.hub_deployment_name}-${var.environment}-dns"
  hub_network_resource_group_name = "rg-${var.hub_deployment_name}-${var.environment}-network"
  hub_virtual_network_name        = "vnet-${var.hub_deployment_name}-${var.environment}"

  # The spoke splits itself across four resource groups so each layer
  # can be governed - and handed to a different team - on its own:
  # core for the platform services, network for the network fabric,
  # dns for the private DNS estate and secrets for the platform key
  # vault. Downstream stacks rebuild these names the same way.
  resource_group_name         = "rg-${local.name_suffix}"
  network_resource_group_name = "rg-${local.name_suffix}-network"
  dns_resource_group_name     = "rg-${local.name_suffix}-dns"
  secrets_resource_group_name = "rg-${local.name_suffix}-secrets"

  vnet_name = "vnet-${local.name_suffix}"

  api_management_name = coalesce(
    var.api_management_name,
    "apim-${local.name_suffix}"
  )

  front_door_name = coalesce(
    var.front_door_name,
    "afd-${local.name_suffix}"
  )

  subnet_ids = var.enable_virtual_network ? module.vnet[0].subnet_ids : {}

  integration_subnet_names = toset([
    for name in keys(var.subnets) : name
    if name != var.private_endpoint_subnet_name
    && name != var.container_apps_subnet_name
    && name != var.aks_subnet_name
    && name != var.api_management_subnet_name
    && name != var.application_gateway_subnet_name
    && name != var.private_link_service_subnet_name
    && !contains(var.virtual_machine_subnet_names, name)
    && !contains(var.database_subnet_names, name)
  ])

  integration_subnet_ids = {
    for name in local.integration_subnet_names :
    name => module.vnet[0].subnet_ids[name]
  }

  application_gateway_subnet_prefix = (
    var.subnets[var.application_gateway_subnet_name].address_prefixes[0]
  )

  # The gateway's internal frontend. Published as an output because the
  # hub deploys first and cannot derive it: its firewall DNAT rule names
  # this address by hand, and the two drift silently when they disagree.
  application_gateway_private_ip_address = cidrhost(local.application_gateway_subnet_prefix, 10)

  api_management_host_names = toset([
    "${local.api_management_name}.azure-api.net",
    "${local.api_management_name}.developer.azure-api.net",
    "${local.api_management_name}.management.azure-api.net",
    "${local.api_management_name}.scm.azure-api.net",
    "${local.api_management_name}.portal.azure-api.net",
  ])

  virtual_machine_subnet_prefixes = flatten([
    for name in var.virtual_machine_subnet_names :
    var.subnets[name].address_prefixes
  ])

  private_endpoint_subnet_prefixes = (
    var.subnets[var.private_endpoint_subnet_name].address_prefixes
  )

  container_apps_subnet_prefixes = (
    var.subnets[var.container_apps_subnet_name].address_prefixes
  )

  aks_subnet_prefixes = (
    var.subnets[var.aks_subnet_name].address_prefixes
  )

  # With Azure CNI overlay, cross-node pod traffic travels the node
  # subnet carrying overlay pod CIDR addresses, so cluster-internal
  # rules must cover the node subnet and the pod range together.
  aks_cluster_internal_prefixes = concat(
    local.aks_subnet_prefixes,
    [var.aks_pod_cidr]
  )

  # The Environment tag holds the standard name of the environment,
  # while var.environment keeps the short form every resource name is
  # derived from - so the tag standard renames nothing.
  standard_environment_tags = {
    rd   = "RD"
    dev  = "Development"
    qa   = "QA"
    prod = "Production"
  }

  # The optional tags only join the set once they have a value, so no
  # resource carries an empty ExpiryDate, BusinessUnit or Repository.
  optional_tags = merge(
    var.expiry_date != null ? { ExpiryDate = var.expiry_date } : {},
    var.business_unit != null ? { BusinessUnit = var.business_unit } : {},
    var.repository != null ? { Repository = var.repository } : {},
  )

  # The tag set every resource in this stack carries: set on the
  # resources declared here and passed to every shared module, so
  # each resource is tagged in its own right rather than relying on
  # resource group tag inheritance. var.tags is merged last, so a
  # deployment can add to - or override - the standard values.
  common_tags = merge(
    {
      Application        = coalesce(var.application, var.deployment_name)
      Environment        = coalesce(var.environment_tag, lookup(local.standard_environment_tags, lower(var.environment), null))
      Owner              = var.owner
      CostCenter         = coalesce(var.cost_center, var.application, var.deployment_name)
      ManagedBy          = "Terraform"
      Criticality        = var.criticality
      Service            = var.service
      DataClassification = var.data_classification
      Lifecycle          = var.lifecycle_stage
    },
    local.optional_tags,
    var.tags,
  )
}

# ------------------------------------------------------------
# Resource groups
#
# The spoke is split four ways so each layer can be governed - and
# handed to a different team - on its own:
#
#   core     the platform services the spoke offers its workloads:
#            API Management, Front Door and the application gateway
#   network  the network fabric: the virtual network, its network
#            security and application security groups, and the NAT
#            gateway
#   dns      the private DNS zones the spoke owns
#   secrets  the platform key vault
#
# The core, network and DNS groups are always created, whichever
# components the environment enables, so the layout - and the role and
# policy assignments scoped to it - is the same in every environment,
# and an operator knows where a component lands before it is turned
# on. The secrets group only exists alongside the vault it holds.
#
# Two rules keep the split unambiguous: private endpoints live with
# the resource they publish rather than in the network group, so a
# service and its only entry point are never split apart; and a
# service that merely sits in a subnet stays in core with the rest of
# the platform, so the network group holds the fabric alone.
# ------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.deployment_location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "network" {
  name     = local.network_resource_group_name
  location = var.deployment_location
  tags     = local.common_tags
}

resource "azurerm_resource_group" "dns" {
  name     = local.dns_resource_group_name
  location = var.deployment_location
  tags     = local.common_tags
}

# ------------------------------------------------------------
# Application spoke virtual network
#
# Only the virtual network and its network security groups deploy by
# default; peering, DNS zone links, API Management, Front Door and the
# application gateway are opt-in through enable_* flags. Each App
# Service application gets its own
# delegated subnet for regional virtual network integration, each
# virtual machine workload gets its own subnet, and the container apps
# environment gets a delegated infrastructure subnet. Private
# endpoints for all applications land in a dedicated subnet.
# ------------------------------------------------------------

module "vnet" {
  source = "../../shared/vnet"

  count = var.enable_virtual_network ? 1 : 0

  name                = local.vnet_name
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  address_space       = var.address_space
  dns_servers         = var.dns_servers
  subnets             = var.subnets
  tags                = local.common_tags
}

# Private endpoints only ever receive traffic, so allow HTTPS from
# within the network and deny everything else.
module "nsg_private_endpoints" {
  source = "../../shared/nsg"

  count = var.enable_virtual_network ? 1 : 0

  name                = "nsg-${local.name_suffix}-pe"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = local.common_tags

  subnet_associations = {
    private-endpoints = local.subnet_ids[var.private_endpoint_subnet_name]
  }

  security_rules = [
    {
      name                       = "AllowHttpsInbound"
      description                = "Allow HTTPS to private endpoints from the hub and spoke network."
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowSmbInbound"
      description                = "Allow SMB to file share private endpoints, e.g. the Logic Apps runtime content share."
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "445"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowSqlInbound"
      description                = "Allow SQL clients to database private endpoints."
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "1433"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowAmqpInbound"
      description                = "Allow AMQP to messaging private endpoints, e.g. Service Bus and Event Hubs."
      priority                   = 130
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["5671", "5672"]
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowRedisTlsInbound"
      description                = "Allow the Redis TLS port to cache private endpoints."
      priority                   = 140
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "6380"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "DenyAllInbound"
      description                = "Deny all other inbound traffic."
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      destination_address_prefix = "*"
    }
  ]
}

# Application security groups the VM workloads' network interfaces
# join (through the VM stacks' application_security_group_name input).
# The VM subnet NSG below targets these instead of address prefixes,
# so rules follow the workload and scale-out needs no rule changes.
module "asg_linux_virtual_machines" {
  source = "../../shared/application-security-group"

  count = var.enable_virtual_network ? 1 : 0

  name                = "asg-${local.name_suffix}-linux-vm"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = local.common_tags
}

module "asg_windows_virtual_machines" {
  source = "../../shared/application-security-group"

  count = var.enable_virtual_network ? 1 : 0

  name                = "asg-${local.name_suffix}-windows-vm"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = local.common_tags
}

# Virtual machine subnets only receive management traffic from Azure
# Bastion in the hub, targeted at the workload ASGs; outbound traffic
# is limited to DNS, the private endpoints, the network and web
# egress (which the hub firewall inspects when routes send it there).
# Everything else, in both directions, is denied. Machines must join
# their workload's ASG or the allow rules do not match them.
module "nsg_virtual_machines" {
  source = "../../shared/nsg"

  count = var.enable_virtual_network ? 1 : 0

  name                = "nsg-${local.name_suffix}-vm"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = local.common_tags

  subnet_associations = {
    for name in toset(var.virtual_machine_subnet_names) :
    name => local.subnet_ids[name]
  }

  security_rules = concat([
    {
      name                                       = "AllowBastionSshInbound"
      description                                = "Allow SSH from the Azure Bastion subnet to the Linux machines."
      priority                                   = 100
      direction                                  = "Inbound"
      access                                     = "Allow"
      protocol                                   = "Tcp"
      source_port_range                          = "*"
      destination_port_range                     = "22"
      source_address_prefix                      = var.bastion_source_address_prefix
      destination_application_security_group_ids = [module.asg_linux_virtual_machines[0].id]
    },
    {
      name                                       = "AllowBastionRdpInbound"
      description                                = "Allow RDP from the Azure Bastion subnet to the Windows machines."
      priority                                   = 110
      direction                                  = "Inbound"
      access                                     = "Allow"
      protocol                                   = "Tcp"
      source_port_range                          = "*"
      destination_port_range                     = "3389"
      source_address_prefix                      = var.bastion_source_address_prefix
      destination_application_security_group_ids = [module.asg_windows_virtual_machines[0].id]
    },
    {
      name                         = "AllowAzureLoadBalancerInbound"
      description                  = "Allow Azure Load Balancer health probes, needed by the VM stacks' internal load balancers."
      priority                     = 120
      direction                    = "Inbound"
      access                       = "Allow"
      protocol                     = "*"
      source_port_range            = "*"
      destination_port_range       = "*"
      source_address_prefix        = "AzureLoadBalancer"
      destination_address_prefixes = local.virtual_machine_subnet_prefixes
    },
    {
      name                       = "DenyAllInbound"
      description                = "Deny all other inbound traffic."
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
    {
      name                                  = "AllowDnsOutbound"
      description                           = "Allow DNS from the machines to resolvers on the network, e.g. Azure DNS, the hub's DNS resolver or domain controllers."
      priority                              = 200
      direction                             = "Outbound"
      access                                = "Allow"
      protocol                              = "*"
      source_port_range                     = "*"
      destination_port_range                = "53"
      source_application_security_group_ids = [module.asg_linux_virtual_machines[0].id, module.asg_windows_virtual_machines[0].id]
      destination_address_prefix            = "VirtualNetwork"
    },
    {
      name                                  = "AllowPrivateEndpointsOutbound"
      description                           = "Allow the machines to reach the spoke's private endpoints: HTTPS, SMB, SQL and Service Bus."
      priority                              = 210
      direction                             = "Outbound"
      access                                = "Allow"
      protocol                              = "Tcp"
      source_port_range                     = "*"
      destination_port_ranges               = ["443", "445", "1433", "5671-5672"]
      source_application_security_group_ids = [module.asg_linux_virtual_machines[0].id, module.asg_windows_virtual_machines[0].id]
      destination_address_prefixes          = local.private_endpoint_subnet_prefixes
    },
    {
      name                                  = "AllowVnetHttpsOutbound"
      description                           = "Allow HTTPS from the machines to the hub and spoke network, e.g. the monitoring spoke's private ingestion endpoints."
      priority                              = 220
      direction                             = "Outbound"
      access                                = "Allow"
      protocol                              = "Tcp"
      source_port_range                     = "*"
      destination_port_range                = "443"
      source_application_security_group_ids = [module.asg_linux_virtual_machines[0].id, module.asg_windows_virtual_machines[0].id]
      destination_address_prefix            = "VirtualNetwork"
    },
    {
      name                                  = "AllowInternetWebOutbound"
      description                           = "Allow web egress from the machines for OS packages and updates. The hub firewall inspects this when routes send spoke egress through it."
      priority                              = 230
      direction                             = "Outbound"
      access                                = "Allow"
      protocol                              = "Tcp"
      source_port_range                     = "*"
      destination_port_ranges               = ["80", "443"]
      source_application_security_group_ids = [module.asg_linux_virtual_machines[0].id, module.asg_windows_virtual_machines[0].id]
      destination_address_prefix            = "Internet"
    },
    {
      name                                  = "AllowNtpOutbound"
      description                           = "Allow NTP time synchronisation from the machines."
      priority                              = 240
      direction                             = "Outbound"
      access                                = "Allow"
      protocol                              = "Udp"
      source_port_range                     = "*"
      destination_port_range                = "123"
      source_application_security_group_ids = [module.asg_linux_virtual_machines[0].id, module.asg_windows_virtual_machines[0].id]
      destination_address_prefix            = "Internet"
    },
    {
      name                                  = "AllowKmsOutbound"
      description                           = "Allow Windows activation traffic to the Azure KMS endpoints."
      priority                              = 250
      direction                             = "Outbound"
      access                                = "Allow"
      protocol                              = "Tcp"
      source_port_range                     = "*"
      destination_port_range                = "1688"
      source_application_security_group_ids = [module.asg_windows_virtual_machines[0].id]
      destination_address_prefix            = "Internet"
    },
    {
      name                       = "DenyAllOutbound"
      description                = "Deny all other outbound traffic from the virtual machine subnets."
      priority                   = 4096
      direction                  = "Outbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
    ],
    # Active Directory traffic from the Windows machines to the domain
    # controllers, only when domain controllers are configured:
    # Kerberos, LDAP(S), SMB, RPC, global catalog, password changes,
    # DNS and W32Time.
    length(var.active_directory_outbound_address_prefixes) == 0 ? [] : [
      {
        name                                  = "AllowActiveDirectoryTcpOutbound"
        description                           = "Allow TCP Active Directory traffic from the Windows machines to the domain controllers."
        priority                              = 260
        direction                             = "Outbound"
        access                                = "Allow"
        protocol                              = "Tcp"
        source_port_range                     = "*"
        destination_port_ranges               = ["53", "88", "135", "389", "445", "464", "636", "3268-3269", "49152-65535"]
        source_application_security_group_ids = [module.asg_windows_virtual_machines[0].id]
        destination_address_prefixes          = var.active_directory_outbound_address_prefixes
      },
      {
        name                                  = "AllowActiveDirectoryUdpOutbound"
        description                           = "Allow UDP Active Directory traffic from the Windows machines to the domain controllers."
        priority                              = 270
        direction                             = "Outbound"
        access                                = "Allow"
        protocol                              = "Udp"
        source_port_range                     = "*"
        destination_port_ranges               = ["53", "88", "123", "389", "464"]
        source_application_security_group_ids = [module.asg_windows_virtual_machines[0].id]
        destination_address_prefixes          = var.active_directory_outbound_address_prefixes
      }
    ],
    # Workload traffic into the machines, e.g. through the VM stacks'
    # load balancers - kept aligned with the ports and protocols those
    # stacks' load_balancer_rules expose. Each rule carries its own
    # source, so a workload published through a public frontend opens
    # to the internet without widening the rest.
    [
      for index, rule in var.virtual_machine_workload_inbound_rules : {
        name                                       = "AllowWorkloadInbound-${rule.name}"
        description                                = "Allow ${rule.name} workload traffic from ${rule.source_address_prefix} to the machines."
        priority                                   = 130 + index * 10
        direction                                  = "Inbound"
        access                                     = "Allow"
        protocol                                   = rule.protocol
        source_port_range                          = "*"
        destination_port_ranges                    = rule.port_ranges
        source_address_prefix                      = rule.source_address_prefix
        destination_application_security_group_ids = [module.asg_linux_virtual_machines[0].id, module.asg_windows_virtual_machines[0].id]
      }
  ])
}

# Integration subnets host outbound App Service traffic only and never
# receive inbound connections.
module "nsg_integration" {
  source = "../../shared/nsg"

  count = var.enable_virtual_network ? 1 : 0

  name                = "nsg-${local.name_suffix}-integration"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = local.common_tags

  subnet_associations = local.integration_subnet_ids

  security_rules = [
    {
      name                       = "DenyAllInbound"
      description                = "Integration subnets never receive inbound traffic."
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  ]
}

# The container apps infrastructure subnet accepts ingress from within
# the network plus the platform traffic the environment needs: traffic
# between its own infrastructure addresses and Azure Load Balancer
# health probes.
module "nsg_container_apps" {
  source = "../../shared/nsg"

  count = var.enable_virtual_network ? 1 : 0

  name                = "nsg-${local.name_suffix}-aca"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = local.common_tags

  subnet_associations = {
    container-apps = local.subnet_ids[var.container_apps_subnet_name]
  }

  security_rules = [
    {
      name                         = "AllowIntraSubnetInbound"
      description                  = "Allow traffic between the environment's infrastructure addresses."
      priority                     = 100
      direction                    = "Inbound"
      access                       = "Allow"
      protocol                     = "*"
      source_port_range            = "*"
      destination_port_range       = "*"
      source_address_prefixes      = local.container_apps_subnet_prefixes
      destination_address_prefixes = local.container_apps_subnet_prefixes
    },
    {
      name                       = "AllowHttpsInbound"
      description                = "Allow HTTP and HTTPS ingress from the hub and spoke network. HTTP is redirected to HTTPS by the environment."
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["80", "443"]
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowAzureLoadBalancerInbound"
      description                = "Allow Azure Load Balancer traffic to the environment's infrastructure. The platform needs both TCP and UDP on this range."
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "30000-32767"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "*"
    },
    {
      name                       = "DenyAllInbound"
      description                = "Deny all other inbound traffic."
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  ]
}

# The AKS node subnet accepts workload ingress from within the network
# on HTTP and HTTPS - reaching the cluster's internal load balancer
# frontends, which is what a LoadBalancer service publishes - plus the
# platform traffic the cluster needs: cluster-internal traffic and
# Azure Load Balancer health probes. Publishing a service on any other
# port means widening AllowWebInbound to cover it; node ports are not
# reachable from the network, only through a load balancer frontend:
# Azure matches these rules against the frontend's address and the
# service port, not the node address and node port behind it.
#
# Because the cluster uses Azure CNI overlay, cross-node pod traffic
# (including pod DNS queries to CoreDNS) arrives with overlay pod CIDR
# addresses, not node addresses - so with the explicit deny-all rule in
# place, the cluster-internal allowance must cover the node subnet and
# the pod range (aks_pod_cidr) in every direction: node-to-node,
# node-to-pod, pod-to-node and pod-to-pod.
module "nsg_aks" {
  source = "../../shared/nsg"

  count = var.enable_virtual_network ? 1 : 0

  name                = "nsg-${local.name_suffix}-aks"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = local.common_tags

  subnet_associations = {
    aks = local.subnet_ids[var.aks_subnet_name]
  }

  security_rules = [
    {
      name                         = "AllowAksClusterInternalInbound"
      description                  = "Allow cluster-internal traffic between the nodes and the overlay pod range, which cross-node pod traffic carries."
      priority                     = 100
      direction                    = "Inbound"
      access                       = "Allow"
      protocol                     = "*"
      source_port_range            = "*"
      destination_port_range       = "*"
      source_address_prefixes      = local.aks_cluster_internal_prefixes
      destination_address_prefixes = local.aks_cluster_internal_prefixes
    },
    {
      name                       = "AllowWebInbound"
      description                = "Allow HTTP and HTTPS from the hub and spoke network to the cluster's internal load balancer frontends."
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["80", "443"]
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowAzureLoadBalancerInbound"
      description                = "Allow Azure Load Balancer health probes to the nodes. The platform probes the node ports its load balancing rules target."
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "*"
    },
    {
      name                       = "DenyAllInbound"
      description                = "Deny all other inbound traffic."
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
    # This NSG defines no custom outbound deny, so the default outbound
    # rules still allow node egress: the API server and Azure platform
    # over the load balancer outbound path, and image pulls through the
    # registry's private endpoint. The explicit rule keeps
    # cluster-internal flows working whatever the service tags make of
    # the overlay range - and keeps working if a custom outbound
    # deny-all is ever added alongside it.
    {
      name                         = "AllowAksClusterInternalOutbound"
      description                  = "Allow cluster-internal traffic between the nodes and the overlay pod range, which cross-node pod traffic carries."
      priority                     = 100
      direction                    = "Outbound"
      access                       = "Allow"
      protocol                     = "*"
      source_port_range            = "*"
      destination_port_range       = "*"
      source_address_prefixes      = local.aks_cluster_internal_prefixes
      destination_address_prefixes = local.aks_cluster_internal_prefixes
    }
  ]
}

# The API Management subnet accepts gateway traffic from within the
# network plus the platform traffic an internal instance needs: the
# management endpoint and Azure Load Balancer health probes.
module "nsg_api_management" {
  source = "../../shared/nsg"

  count = var.enable_virtual_network ? 1 : 0

  name                = "nsg-${local.name_suffix}-apim"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = local.common_tags

  subnet_associations = {
    api-management = local.subnet_ids[var.api_management_subnet_name]
  }

  security_rules = [
    {
      name                       = "AllowHttpsInbound"
      description                = "Allow HTTPS to the gateway from the hub and spoke network."
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowApiManagementInbound"
      description                = "Allow the API Management control plane to manage the instance."
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3443"
      source_address_prefix      = "ApiManagement"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowAzureLoadBalancerInbound"
      description                = "Allow Azure Load Balancer health probes to the instance."
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "6390"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "DenyAllInbound"
      description                = "Deny all other inbound traffic."
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  ]
}

# The application gateway subnet accepts gateway traffic from within
# the network plus the platform traffic the v2 SKU needs: the gateway
# manager control plane and Azure Load Balancer health probes.
module "nsg_application_gateway" {
  source = "../../shared/nsg"

  count = var.enable_virtual_network ? 1 : 0

  name                = "nsg-${local.name_suffix}-agw"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = local.common_tags

  subnet_associations = {
    app-gateway = local.subnet_ids[var.application_gateway_subnet_name]
  }

  security_rules = [
    {
      name                       = "AllowWebInbound"
      description                = "Allow HTTP and HTTPS to the gateway listeners from the hub and spoke network."
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["80", "443"]
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowGatewayManagerInbound"
      description                = "Allow the gateway manager control plane to manage the v2 gateway."
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "65200-65535"
      source_address_prefix      = "GatewayManager"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowAzureLoadBalancerInbound"
      description                = "Allow Azure Load Balancer health probes to the gateway."
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "*"
    },
    {
      name                       = "DenyAllInbound"
      description                = "Deny all other inbound traffic."
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  ]
}

# The private link service subnet holds nothing but the NAT addresses a
# private link service translates consumer connections through - e.g.
# the aks stack's, publishing the cluster's internal load balancer to
# Front Door.
#
# Azure does not apply this network security group to that NAT traffic:
# the subnet disables its private link service network policies, which
# is exactly what turns the filtering off, and a private link service
# cannot take NAT addresses from a subnet that keeps them on. The group
# is attached anyway so the subnet is not the one hole in a spoke whose
# every other subnet ends in a deny-all - it governs anything else that
# lands here, and nothing else should.
module "nsg_private_link_service" {
  source = "../../shared/nsg"

  count = var.enable_virtual_network ? 1 : 0

  name                = "nsg-${local.name_suffix}-pls"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = local.common_tags

  subnet_associations = {
    private-link-service = local.subnet_ids[var.private_link_service_subnet_name]
  }

  security_rules = [
    {
      name                       = "DenyAllInbound"
      description                = "Deny all other inbound traffic. Not applied to the private link service's own NAT traffic, which bypasses network security groups."
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  ]
}

# Database flexible server subnets only accept their database protocol
# from inside the network, plus the platform traffic the managed
# service itself needs.
module "nsg_databases" {
  source = "../../shared/nsg"

  count = var.enable_virtual_network ? 1 : 0

  name                = "nsg-${local.name_suffix}-db"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  tags                = local.common_tags

  subnet_associations = {
    for name in toset(var.database_subnet_names) :
    name => local.subnet_ids[name]
  }

  security_rules = [
    {
      name                       = "AllowPostgresInbound"
      description                = "Allow PostgreSQL clients from the hub and spoke network."
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "5432"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowMysqlInbound"
      description                = "Allow MySQL clients from the hub and spoke network."
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3306"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "AllowAzureLoadBalancerInbound"
      description                = "Allow the platform load balancer probes the flexible servers rely on."
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "*"
    },
    {
      name                       = "DenyAllInbound"
      description                = "Deny all other inbound traffic."
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  ]
}

# Explicit outbound path for the virtual machine subnets (optional).
# Standard internal load balancers provide no outbound connectivity,
# so load-balanced machines get theirs from this NAT gateway - or from
# a route through the hub firewall, in which case leave it disabled.
module "nat_gateway" {
  source = "../../shared/nat-gateway"

  count = var.enable_virtual_network && var.enable_nat_gateway ? 1 : 0

  name                = "ng-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  zone                = var.nat_gateway_zone
  tags                = local.common_tags

  subnet_ids = {
    for name in var.virtual_machine_subnet_names : name => local.subnet_ids[name]
  }
}

# ------------------------------------------------------------
# Peering with the hub (optional)
# ------------------------------------------------------------

data "azurerm_virtual_network" "hub" {
  provider = azurerm.hub

  count = var.enable_hub_peering ? 1 : 0

  name                = local.hub_virtual_network_name
  resource_group_name = local.hub_network_resource_group_name
}

module "hub_peering" {
  source = "../../shared/vnet-peering"

  count = var.enable_virtual_network && var.enable_hub_peering ? 1 : 0

  providers = {
    azurerm.hub = azurerm.hub
  }

  hub_virtual_network = {
    id                  = data.azurerm_virtual_network.hub[0].id
    name                = data.azurerm_virtual_network.hub[0].name
    resource_group_name = local.hub_network_resource_group_name
  }

  spoke_virtual_network = {
    id                  = module.vnet[0].id
    name                = module.vnet[0].name
    resource_group_name = azurerm_resource_group.network.name
  }

  allow_gateway_transit = var.use_hub_gateway
  use_remote_gateways   = var.use_hub_gateway
}

# Link the spoke to the hub's private DNS zones so private endpoint
# names resolve from inside the spoke (optional). The links live with
# the zones in the hub, so they are created through the hub provider.
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  provider = azurerm.hub

  for_each = var.enable_virtual_network && var.enable_hub_dns_zone_links ? toset(concat(var.hub_private_dns_zone_names, var.additional_hub_private_dns_zone_names)) : []

  name                  = "link-${local.vnet_name}"
  resource_group_name   = local.hub_dns_resource_group_name
  private_dns_zone_name = each.value
  virtual_network_id    = module.vnet[0].id
  registration_enabled  = false
  tags                  = local.common_tags
}

# ------------------------------------------------------------
# API Management (optional) - internal gateway for the spoke's APIs
# ------------------------------------------------------------

module "api_management" {
  source = "../../shared/api-management"

  count = var.enable_virtual_network && var.enable_api_management ? 1 : 0

  name                = local.api_management_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  publisher_name      = var.api_management_publisher_name
  publisher_email     = var.api_management_publisher_email
  sku_name            = var.api_management_sku
  subnet_id           = local.subnet_ids[var.api_management_subnet_name]
  tags                = local.common_tags
}

# Azure publishes no DNS for internal instances, so each default
# hostname gets its own narrowly scoped private zone with an apex
# record, linked to the spoke and to the hub when peered. One zone per
# hostname avoids making the private zone authoritative for the whole
# azure-api.net suffix, which would break resolution of other public
# API Management instances from the linked networks.
module "api_management_dns_zone" {
  source = "../../shared/private-dns-zone"

  for_each = var.enable_virtual_network && var.enable_api_management ? local.api_management_host_names : []

  name                = each.value
  resource_group_name = azurerm_resource_group.dns.name
  tags                = local.common_tags

  a_records = {
    "@" = {
      records = module.api_management[0].private_ip_addresses
    }
  }

  virtual_network_links = merge(
    {
      (local.vnet_name) = {
        virtual_network_id = module.vnet[0].id
      }
    },
    var.enable_hub_peering ? {
      (local.hub_virtual_network_name) = {
        virtual_network_id = data.azurerm_virtual_network.hub[0].id
      }
    } : {}
  )
}

# ------------------------------------------------------------
# Front Door (optional) - global entry point for the spoke's
# applications
#
# Only the profile lives here. Each application adds its own endpoint,
# origin and route with the front-door-endpoint module, reaching its
# origin over Private Link.
# ------------------------------------------------------------

module "front_door" {
  source = "../../shared/front-door"

  count = var.enable_front_door ? 1 : 0

  name                = local.front_door_name
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = var.front_door_sku
  tags                = local.common_tags
}

# ------------------------------------------------------------
# Application Gateway (optional) - regional entry point with an
# internal listener
# ------------------------------------------------------------

module "application_gateway" {
  source = "../../shared/application-gateway"

  count = var.enable_virtual_network && var.enable_application_gateway ? 1 : 0

  name                = "agw-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  subnet_id           = local.subnet_ids[var.application_gateway_subnet_name]
  private_ip_address  = local.application_gateway_private_ip_address
  sku_name            = var.application_gateway_sku
  sku_tier            = var.application_gateway_sku
  zones               = var.application_gateway_zones
  tags                = local.common_tags

  # Either named backends (web apps) or addressed ones - the AKS
  # cluster's internal load balancer frontend has no name of its own,
  # so publishing it means pointing the pool at aks_ingress_ip_address
  # over plain HTTP on port 80.
  backend_fqdns        = var.application_gateway_backend_fqdns
  backend_ip_addresses = var.application_gateway_backend_ip_addresses
  backend_protocol     = var.application_gateway_backend_protocol
  backend_port         = var.application_gateway_backend_port
  backend_probe_path   = var.application_gateway_backend_probe_path
}

# ------------------------------------------------------------
# Platform key vault (optional), in its own dedicated resource group
#
# Administrators pre-load secrets here through the Secrets Officer
# role from inside the network, ahead of the deployments that need
# them. Applications then retrieve secrets dynamically - at runtime
# with key vault references and their managed identities, or at
# deployment time with data sources from an agent that can reach the
# vault's private data plane.
# ------------------------------------------------------------

resource "azurerm_resource_group" "secrets" {
  count = var.enable_platform_key_vault ? 1 : 0

  name     = local.secrets_resource_group_name
  location = var.deployment_location
  tags     = local.common_tags
}

data "azurerm_private_dns_zone" "key_vault" {
  provider = azurerm.hub

  count = var.enable_platform_key_vault ? 1 : 0

  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = local.hub_dns_resource_group_name
}

module "platform_key_vault" {
  source = "../../shared/key-vault"

  count = var.enable_platform_key_vault ? 1 : 0

  name                = coalesce(var.platform_key_vault_name, "kv-${local.name_suffix}")
  resource_group_name = azurerm_resource_group.secrets[0].name
  location            = azurerm_resource_group.secrets[0].location
  tags                = local.common_tags

  secrets_officer_principal_ids = var.platform_key_vault_secrets_officer_principal_ids
}

module "platform_key_vault_private_endpoint" {
  source = "../../shared/private-endpoint"

  count = var.enable_platform_key_vault ? 1 : 0

  name                           = "pep-${module.platform_key_vault[0].name}"
  resource_group_name            = azurerm_resource_group.secrets[0].name
  location                       = azurerm_resource_group.secrets[0].location
  subnet_id                      = local.subnet_ids[var.private_endpoint_subnet_name]
  private_connection_resource_id = module.platform_key_vault[0].id
  subresource_names              = ["vault"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.key_vault[0].id]
  tags                           = local.common_tags
}

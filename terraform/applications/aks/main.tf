locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  # The upstream stacks this one looks up derive their names the
  # same way, from their own workload name and this environment.
  app_spoke_network_resource_group_name = "rg-${var.app_spoke_deployment_name}-${var.environment}-network"
  app_spoke_resource_group_name         = "rg-${var.app_spoke_deployment_name}-${var.environment}"
  app_spoke_virtual_network_name        = "vnet-${var.app_spoke_deployment_name}-${var.environment}"
  application_gateway_name              = coalesce(var.application_gateway_name, "agw-${var.app_spoke_deployment_name}-${var.environment}")
  front_door_profile_name               = coalesce(var.front_door_profile_name, "afd-${var.app_spoke_deployment_name}-${var.environment}")
  hub_dns_resource_group_name           = "rg-${var.hub_deployment_name}-${var.environment}-dns"
  log_analytics_workspace_name          = "log-${var.monitoring_deployment_name}-${var.environment}"
  monitoring_resource_group_name        = "rg-${var.monitoring_deployment_name}-${var.environment}"

  resource_group_name     = "rg-${local.name_suffix}"
  cluster_name            = "aks-${local.name_suffix}"
  container_registry_name = coalesce(var.container_registry_name, "cr${replace(local.name_suffix, "-", "")}")

  aks_subnet_nsg_id = data.azurerm_subnet.aks.network_security_group_id

  # The overlay range, split into the network address and prefix length
  # the NSG cross-check below compares each rule's address prefixes
  # against. A rule prefix covers the overlay range when it is no
  # longer than this prefix length and shares this network address at
  # that length.
  pod_cidr_network       = cidrhost(var.pod_cidr, 0)
  pod_cidr_prefix_length = tonumber(split("/", var.pod_cidr)[1])

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

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.deployment_location
  tags     = local.common_tags
}

# ------------------------------------------------------------
# Existing platform resources: the application spoke network, the
# hub's private DNS zones and the monitoring workspace.
# ------------------------------------------------------------

data "azurerm_subnet" "aks" {
  provider = azurerm.app_spoke

  name                 = var.aks_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

# The spoke network's routed ranges - its own address space and its
# peered networks' - which the cluster's overlay and service ranges
# must stay outside of.
data "azurerm_virtual_network" "app_spoke" {
  provider = azurerm.app_spoke

  name                = local.app_spoke_virtual_network_name
  resource_group_name = local.app_spoke_network_resource_group_name
}

# The spoke attaches an NSG to the AKS subnet whose cluster-internal
# allowance it generates from its aks_pod_cidr input - a value this
# stack cannot set, only match. Read the attached NSG back and refuse
# to plan while no inbound allow rule covers this stack's pod_cidr on
# both sides: with a mismatch, the NSG's deny-all rule silently drops
# cross-node pod traffic, including pod DNS queries to CoreDNS.
#
# A rule covers the overlay range when a side's prefixes hold the "any"
# wildcard or a CIDR range containing pod_cidr - a range named verbatim
# (what the spoke writes) or any supernet of it, so a network that
# allows the overlay range through a wider prefix passes too. Service
# tags are left uncovered on purpose: VirtualNetwork spans the routed
# ranges the overlay range must stay outside of, so no tag stands in
# for it. Rules scoped by application security group carry no prefixes
# at all and cover nothing here.
data "azurerm_network_security_group" "aks" {
  provider = azurerm.app_spoke

  count = local.aks_subnet_nsg_id == null || local.aks_subnet_nsg_id == "" ? 0 : 1

  name                = split("/", local.aks_subnet_nsg_id)[8]
  resource_group_name = split("/", local.aks_subnet_nsg_id)[4]

  lifecycle {
    postcondition {
      condition = anytrue([
        for rule in self.security_rule :
        alltrue([
          # Both sides of the rule have to cover the overlay range:
          # cross-node pod traffic carries pod addresses as source and
          # destination alike.
          for prefixes in [
            concat(tolist(rule.source_address_prefixes), [rule.source_address_prefix]),
            concat(tolist(rule.destination_address_prefixes), [rule.destination_address_prefix]),
          ] :
          anytrue([
            for prefix in prefixes :
            # try() turns the prefixes that are not CIDR ranges - the
            # service tags, the empty string a side left unset reads
            # back as - into "does not cover" instead of an error.
            prefix == "*" || try(
              tonumber(split("/", prefix)[1]) <= local.pod_cidr_prefix_length &&
              cidrhost(prefix, 0) == cidrhost("${local.pod_cidr_network}/${split("/", prefix)[1]}", 0),
              false
            )
          ])
        ])
        if rule.direction == "Inbound" && rule.access == "Allow"
      ])
      error_message = "No inbound allow rule in ${self.name} covers pod_cidr (${var.pod_cidr}) on both sides, so the network security group attached to the AKS subnet would drop cross-node pod traffic at its deny-all rule. Set the spoke's aks_pod_cidr to this stack's pod_cidr and apply the spoke first."
    }
  }
}

data "azurerm_subnet" "private_endpoints" {
  provider = azurerm.app_spoke

  name                 = var.private_endpoint_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

data "azurerm_private_dns_zone" "container_registry" {
  provider = azurerm.hub

  name                = "privatelink.azurecr.io"
  resource_group_name = local.hub_dns_resource_group_name
}

data "azurerm_log_analytics_workspace" "monitoring" {
  provider = azurerm.monitoring

  name                = local.log_analytics_workspace_name
  resource_group_name = local.monitoring_resource_group_name
}

# ------------------------------------------------------------
# AKS cluster - example Kubernetes workload platform
#
# The cluster's nodes join the spoke's AKS subnet with Azure CNI
# overlay networking, and the example workload is published through an
# internal load balancer whose frontend lands in the same subnet, so
# it is only reachable from inside the network. The cluster runs with
# a user-assigned identity so the subnet role assignment it needs can
# exist before the cluster does.
# ------------------------------------------------------------

module "cluster_identity" {
  source = "../../shared/user-assigned-identity"

  name                = "id-${local.name_suffix}-aks"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags
}

# The cluster manages its network presence in the spoke's subnet -
# joining nodes and creating internal load balancer frontends - so its
# identity needs Network Contributor there before it deploys.
module "cluster_network_contributor_role" {
  source = "../../shared/rbac-role-assignment"

  scope                = data.azurerm_subnet.aks.id
  role_definition_name = "Network Contributor"
  principal_type       = "ServicePrincipal"

  principals = {
    cluster = module.cluster_identity.principal_id
  }
}

module "aks" {
  source = "../../shared/aks"

  name                = local.cluster_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.aks_sku_tier
  subnet_id           = data.azurerm_subnet.aks.id
  identity_ids        = [module.cluster_identity.id]
  tags                = local.common_tags

  # The example keeps the API server public - restricted to the
  # authorized address ranges - so the pipeline agent can apply the
  # Kubernetes workload below. Enable the private cluster when
  # deployments run from an agent inside the network.
  private_cluster_enabled         = var.private_cluster_enabled
  api_server_authorized_ip_ranges = var.api_server_authorized_ip_ranges
  entra_admin_group_object_ids    = var.entra_admin_group_object_ids

  # The overlay and service ranges, checked by the module against the
  # spoke's routed ranges - its address space and its peered networks'
  # - so overlapping ranges fail at plan time. pod_cidr must equal the
  # spoke's aks_pod_cidr: the spoke builds the AKS subnet NSG's
  # cluster-internal allowance from it, and the NSG data source above
  # blocks the plan on a mismatch.
  pod_cidr       = var.pod_cidr
  service_cidr   = var.service_cidr
  dns_service_ip = var.dns_service_ip
  routed_address_prefixes = concat(
    data.azurerm_virtual_network.app_spoke.address_space,
    data.azurerm_virtual_network.app_spoke.vnet_peerings_addresses,
  )

  system_node_pool = {
    vm_size   = var.node_pool_vm_size
    min_count = var.node_pool_min_count
    max_count = var.node_pool_max_count
    zones     = var.availability_zones
  }

  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.monitoring.id

  depends_on = [module.cluster_network_contributor_role]
}

# ------------------------------------------------------------
# Container registry, pulled from with the kubelet's managed identity
#
# The example workload starts from public images, so the registry is
# where the cluster pulls application images from once they are
# published there - from inside the network by principals granted
# AcrPush through container_registry_push_principal_ids.
# ------------------------------------------------------------

module "container_registry" {
  source = "../../shared/container-registry"

  name                    = local.container_registry_name
  resource_group_name     = azurerm_resource_group.this.name
  location                = azurerm_resource_group.this.location
  push_principal_ids      = var.container_registry_push_principal_ids
  zone_redundancy_enabled = var.container_registry_zone_redundancy_enabled
  tags                    = local.common_tags
}

module "container_registry_private_endpoint" {
  source = "../../shared/private-endpoint"

  name                           = "pep-${local.container_registry_name}"
  resource_group_name            = azurerm_resource_group.this.name
  location                       = azurerm_resource_group.this.location
  subnet_id                      = data.azurerm_subnet.private_endpoints.id
  private_connection_resource_id = module.container_registry.id
  subresource_names              = ["registry"]
  private_dns_zone_ids           = [data.azurerm_private_dns_zone.container_registry.id]
  tags                           = local.common_tags
}

module "registry_pull_role" {
  source = "../../shared/rbac-role-assignment"

  scope                = module.container_registry.id
  role_definition_name = "AcrPull"
  principal_type       = "ServicePrincipal"

  principals = {
    kubelet = module.aks.kubelet_identity_object_id
  }
}

# ------------------------------------------------------------
# Just-in-time operations access
#
# Operators hold no standing access to the workload's resource group.
# Instead the principals in pim_operations_principals (e.g. an
# operations group) are made eligible for the operations role through
# Privileged Identity Management and activate it when needed - with
# multi-factor authentication and a justification, for at most the
# configured duration. Requires Microsoft Entra ID P2 licensing.
# ------------------------------------------------------------

module "operations_pim" {
  source = "../../shared/pim"
  count  = length(var.pim_operations_principals) > 0 ? 1 : 0

  scope                = azurerm_resource_group.this.id
  role_definition_name = var.pim_operations_role_definition_name
  eligible_principals  = var.pim_operations_principals

  role_management_policy = {
    activation = {
      maximum_duration                   = var.pim_operations_maximum_activation_duration
      require_multifactor_authentication = true
      require_justification              = true
    }
  }
}

# ------------------------------------------------------------
# State moves: these role assignments were standalone resources
# before the rbac-role-assignment module, so the moves keep existing
# deployments' assignments in place instead of recreating them.
# ------------------------------------------------------------

moved {
  from = azurerm_role_assignment.cluster_network_contributor
  to   = module.cluster_network_contributor_role.azurerm_role_assignment.this["cluster"]
}

moved {
  from = azurerm_role_assignment.registry_pull
  to   = module.registry_pull_role.azurerm_role_assignment.this["kubelet"]
}

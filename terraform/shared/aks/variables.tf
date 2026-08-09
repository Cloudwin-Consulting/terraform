variable "name" {
  description = "The name of the AKS cluster."
  type        = string
}

variable "resource_group_name" {
  description = "The resource group into which the cluster is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the cluster is deployed."
  type        = string
}

variable "dns_prefix" {
  description = "The DNS prefix of the cluster's API server address. Defaults to the cluster name."
  type        = string
  default     = null
}

variable "kubernetes_version" {
  description = "The Kubernetes version of the control plane. Leave null for the platform's current default. When pinning alongside the patch upgrade channel, use a minor version alias (e.g. 1.32): a full patch version shows drift each time the platform patches the cluster."
  type        = string
  default     = null
}

variable "sku_tier" {
  description = "The SKU tier of the cluster: Free or Standard. Standard adds the uptime SLA and is recommended for production."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "node_resource_group_name" {
  description = "The name of the platform-managed resource group that holds the cluster's infrastructure. Leave null for a generated name."
  type        = string
  default     = null
}

variable "subnet_id" {
  description = "The ID of the subnet the cluster's nodes (and its internal load balancer frontends) join. The cluster identity needs Network Contributor on it."
  type        = string
}

variable "identity_ids" {
  description = "IDs of the user-assigned identities the cluster runs with. Grant the identity Network Contributor on the node subnet before the cluster deploys."
  type        = list(string)

  validation {
    condition     = length(var.identity_ids) > 0
    error_message = "identity_ids must contain at least one user-assigned identity."
  }
}

variable "private_cluster_enabled" {
  description = "Whether the API server is only reachable through its private endpoint. Keep enabled so the control plane is not exposed to the internet; deployments to the cluster then need an agent inside the network."
  type        = bool
  default     = true
}

variable "private_dns_zone_id" {
  description = "The private DNS zone of a private cluster's API server records: a zone ID, System (a platform-managed zone) or None (no zone, public DNS resolving to the private address). The cluster identity needs Private DNS Zone Contributor on a supplied zone."
  type        = string
  default     = "System"
}

variable "api_server_authorized_ip_ranges" {
  description = "Address ranges allowed to reach a public API server, e.g. deployment agent and operator egress addresses. Not supported on private clusters."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.private_cluster_enabled || length(var.api_server_authorized_ip_ranges) == 0
    error_message = "api_server_authorized_ip_ranges only applies when private_cluster_enabled is false."
  }
}

variable "local_account_disabled" {
  description = "Whether the cluster's local certificate-based accounts are disabled. Only disable them on Microsoft Entra ID integrated clusters whose deployments authenticate with Entra ID tokens - the credential outputs are empty without local accounts."
  type        = bool
  default     = false

  validation {
    condition     = !var.local_account_disabled || length(var.entra_admin_group_object_ids) > 0
    error_message = "local_account_disabled requires Microsoft Entra ID integration through entra_admin_group_object_ids."
  }
}

variable "entra_admin_group_object_ids" {
  description = "Object IDs of the Microsoft Entra ID groups granted cluster administrator access. Setting any enables Entra ID integration with Azure RBAC for the data plane."
  type        = list(string)
  default     = []
}

variable "azure_policy_enabled" {
  description = "Whether the Azure Policy add-on audits and enforces policies inside the cluster."
  type        = bool
  default     = true
}

variable "run_command_enabled" {
  description = "Whether the Run Command service can execute commands in the cluster (az aks command invoke). Kept off by default; enable it for private clusters managed without a network path to the API server."
  type        = bool
  default     = false
}

variable "oidc_issuer_enabled" {
  description = "Whether the cluster publishes an OIDC issuer, required for workload identity federation."
  type        = bool
  default     = true
}

variable "workload_identity_enabled" {
  description = "Whether pods can federate Kubernetes service accounts with user-assigned identities, so workloads reach Azure services without holding credentials."
  type        = bool
  default     = true

  validation {
    condition     = !var.workload_identity_enabled || var.oidc_issuer_enabled
    error_message = "workload_identity_enabled requires oidc_issuer_enabled."
  }
}

variable "automatic_upgrade_channel" {
  description = "The control plane's automatic upgrade channel: patch, stable, rapid or node-image. Leave null to only upgrade manually."
  type        = string
  default     = "patch"
}

variable "node_os_upgrade_channel" {
  description = "How the nodes' operating systems receive updates: NodeImage, SecurityPatch, Unmanaged or None."
  type        = string
  default     = "NodeImage"
}

variable "system_node_pool" {
  description = "The cluster's default (system) node pool. Autoscaling is on by default; set auto_scaling_enabled to false and node_count for a fixed size. temporary_name_for_rotation is the stand-in pool's name while changes that recreate the pool roll through."
  type = object({
    name                         = optional(string, "system")
    vm_size                      = optional(string, "Standard_D2s_v3")
    auto_scaling_enabled         = optional(bool, true)
    node_count                   = optional(number, null)
    min_count                    = optional(number, 1)
    max_count                    = optional(number, 3)
    zones                        = optional(list(string), null)
    max_pods                     = optional(number, null)
    os_disk_size_gb              = optional(number, null)
    os_disk_type                 = optional(string, "Managed")
    os_sku                       = optional(string, "AzureLinux")
    only_critical_addons_enabled = optional(bool, false)
    temporary_name_for_rotation  = optional(string, "systemtmp")
    upgrade_max_surge            = optional(string, "10%")
  })
  default = {}

  validation {
    condition     = var.system_node_pool.auto_scaling_enabled || var.system_node_pool.node_count != null
    error_message = "system_node_pool needs node_count when auto_scaling_enabled is false."
  }
}

variable "node_pools" {
  description = "Additional node pools, keyed by pool name. User pools run workloads; a pool with mode System instead extends the control plane's capacity."
  type = map(object({
    vm_size              = string
    mode                 = optional(string, "User")
    auto_scaling_enabled = optional(bool, true)
    node_count           = optional(number, null)
    min_count            = optional(number, 1)
    max_count            = optional(number, 3)
    zones                = optional(list(string), null)
    max_pods             = optional(number, null)
    os_disk_size_gb      = optional(number, null)
    os_disk_type         = optional(string, "Managed")
    os_sku               = optional(string, "AzureLinux")
    node_labels          = optional(map(string), {})
    node_taints          = optional(list(string), [])
    upgrade_max_surge    = optional(string, "10%")
  }))
  default = {}

  validation {
    condition     = alltrue([for pool in var.node_pools : pool.auto_scaling_enabled || pool.node_count != null])
    error_message = "Node pools need node_count when auto_scaling_enabled is false."
  }
}

variable "network_policy" {
  description = "The network policy engine enforcing Kubernetes NetworkPolicy resources: cilium (which also switches the cluster to the Cilium data plane), azure or calico. Leave null to run without one."
  type        = string
  default     = "cilium"
}

variable "outbound_type" {
  description = "The nodes' outbound path: loadBalancer, userDefinedRouting when route tables send egress through a firewall (the subnet then needs its route table before the cluster deploys), or userAssignedNATGateway when a NAT gateway is attached to the subnet. An AKS-managed NAT gateway is not available: it requires an AKS-managed virtual network, and this module always joins an existing subnet."
  type        = string
  default     = "loadBalancer"

  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting", "userAssignedNATGateway"], var.outbound_type)
    error_message = "outbound_type must be loadBalancer, userDefinedRouting or userAssignedNATGateway."
  }
}

variable "pod_cidr" {
  description = "The overlay address range pods draw their addresses from. Never routed outside the cluster, but must not overlap the network's ranges - and cross-node pod traffic carries these addresses on the node subnet, so a custom-deny NSG there must allow traffic between this range and the subnet."
  type        = string
  default     = "10.244.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "pod_cidr must be a valid CIDR range, e.g. 10.244.0.0/16."
  }

  validation {
    # Two CIDR ranges overlap exactly when they share the same network
    # address at the shorter of the two prefix lengths. Guarded so an
    # invalid range fails its own format validation, not this one.
    condition = !can(cidrhost(var.pod_cidr, 0)) || !can(cidrhost(var.service_cidr, 0)) || (
      cidrhost(format("%s/%d", split("/", var.pod_cidr)[0], min(tonumber(split("/", var.pod_cidr)[1]), tonumber(split("/", var.service_cidr)[1]))), 0) !=
      cidrhost(format("%s/%d", split("/", var.service_cidr)[0], min(tonumber(split("/", var.pod_cidr)[1]), tonumber(split("/", var.service_cidr)[1]))), 0)
    )
    error_message = "pod_cidr must not overlap service_cidr."
  }
}

variable "service_cidr" {
  description = "The address range Kubernetes services draw their cluster IPs from. Must not overlap the network's ranges."
  type        = string
  default     = "10.245.0.0/16"

  validation {
    condition     = can(cidrhost(var.service_cidr, 0))
    error_message = "service_cidr must be a valid CIDR range, e.g. 10.245.0.0/16."
  }
}

variable "dns_service_ip" {
  description = "The cluster DNS service's address, from within service_cidr - but not its network address or first address, which the platform reserves."
  type        = string
  default     = "10.245.0.10"

  validation {
    condition     = can(cidrhost("${var.dns_service_ip}/32", 0))
    error_message = "dns_service_ip must be a valid IP address."
  }

  validation {
    # An address lies within a range when re-anchoring it at the
    # range's prefix length yields the range's own network address.
    condition = !can(cidrhost(var.service_cidr, 0)) || !can(cidrhost("${var.dns_service_ip}/32", 0)) || (
      cidrhost(format("%s/%s", var.dns_service_ip, split("/", var.service_cidr)[1]), 0) == cidrhost(var.service_cidr, 0) &&
      var.dns_service_ip != cidrhost(var.service_cidr, 0) &&
      var.dns_service_ip != cidrhost(var.service_cidr, 1)
    )
    error_message = "dns_service_ip must lie within service_cidr, and must not be its network address or first address - the platform reserves those."
  }
}

variable "routed_address_prefixes" {
  description = "Address prefixes routed in the network the nodes join: at minimum the node subnet's prefixes, ideally the full virtual network address space plus peered network ranges - e.g. from the caller's subnet or virtual network data sources. When set, planning fails if pod_cidr or service_cidr overlaps any of them. Leave empty to skip the check."
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "The ID of a Log Analytics workspace receiving Container insights and the control plane's diagnostics. Leave null to skip both."
  type        = string
  default     = null
}

variable "enable_diagnostics" {
  description = "Whether to create the diagnostic setting. Defaults to creating it when log_analytics_workspace_id is set. Set explicitly when the workspace is created in the same apply: its ID is unknown at plan time, so it cannot decide whether the setting exists."
  type        = bool
  default     = null

  validation {
    condition     = var.enable_diagnostics != true || var.log_analytics_workspace_id != null
    error_message = "enable_diagnostics requires log_analytics_workspace_id to be set."
  }
}

variable "enable_key_vault_secrets_provider" {
  description = "Whether the key vault secrets CSI driver mounts vault secrets into pods, kept in sync when secrets rotate."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the cluster and its node pools."
  type        = map(string)
  default     = {}
}

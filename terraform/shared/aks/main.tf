terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

locals {
  # Admin credentials only exist on Microsoft Entra ID integrated
  # clusters; everything else exposes its certificate credentials
  # through kube_config. Fall back so the credential outputs work for
  # both cluster shapes, ending at null so they yield null - not an
  # error - if a cluster exposes no credential blocks at all.
  kube_config = try(azurerm_kubernetes_cluster.this.kube_admin_config[0], azurerm_kubernetes_cluster.this.kube_config[0], null)
}

# The managed cluster. Nodes join an existing subnet with Azure CNI
# overlay networking, so only nodes and internal load balancer
# frontends consume network addresses and pods draw theirs from the
# overlay range.
resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = coalesce(var.dns_prefix, var.name)
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  node_resource_group = var.node_resource_group_name
  tags                = var.tags

  # Secure defaults: a private API server, Kubernetes RBAC, Azure
  # Policy and no Run Command service. Deploying workloads to a private
  # cluster requires an agent that can reach the API server from inside
  # the network.
  private_cluster_enabled           = var.private_cluster_enabled
  private_dns_zone_id               = var.private_cluster_enabled ? var.private_dns_zone_id : null
  role_based_access_control_enabled = true

  # The None zone mode records the API server's private address in
  # public DNS - the cluster's only name - so the public FQDN turns on
  # with it.
  private_cluster_public_fqdn_enabled = var.private_cluster_enabled && var.private_dns_zone_id == "None"
  local_account_disabled              = var.local_account_disabled
  azure_policy_enabled                = var.azure_policy_enabled
  run_command_enabled                 = var.run_command_enabled

  # The OIDC issuer and workload identity let pods federate their
  # service accounts with user-assigned identities instead of holding
  # credentials.
  oidc_issuer_enabled       = var.oidc_issuer_enabled
  workload_identity_enabled = var.workload_identity_enabled

  # The platform keeps the control plane on the latest patch release
  # and the nodes on the latest node image by default.
  automatic_upgrade_channel = var.automatic_upgrade_channel
  node_os_upgrade_channel   = var.node_os_upgrade_channel

  # When the API server stays public, restrict who can reach it.
  dynamic "api_server_access_profile" {
    for_each = length(var.api_server_authorized_ip_ranges) == 0 ? [] : [1]

    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }

  # The cluster runs with a user-assigned identity so role assignments
  # (e.g. Network Contributor on its subnet) can exist before the
  # cluster does.
  identity {
    type         = "UserAssigned"
    identity_ids = var.identity_ids
  }

  # Microsoft Entra ID integration with Azure RBAC for the data plane,
  # enabled by naming the administrator groups.
  dynamic "azure_active_directory_role_based_access_control" {
    for_each = length(var.entra_admin_group_object_ids) == 0 ? [] : [1]

    content {
      admin_group_object_ids = var.entra_admin_group_object_ids
      azure_rbac_enabled     = true
    }
  }

  default_node_pool {
    name                         = var.system_node_pool.name
    vm_size                      = var.system_node_pool.vm_size
    vnet_subnet_id               = var.subnet_id
    zones                        = var.system_node_pool.zones
    auto_scaling_enabled         = var.system_node_pool.auto_scaling_enabled
    node_count                   = var.system_node_pool.node_count
    min_count                    = var.system_node_pool.auto_scaling_enabled ? var.system_node_pool.min_count : null
    max_count                    = var.system_node_pool.auto_scaling_enabled ? var.system_node_pool.max_count : null
    max_pods                     = var.system_node_pool.max_pods
    os_disk_size_gb              = var.system_node_pool.os_disk_size_gb
    os_disk_type                 = var.system_node_pool.os_disk_type
    os_sku                       = var.system_node_pool.os_sku
    only_critical_addons_enabled = var.system_node_pool.only_critical_addons_enabled
    temporary_name_for_rotation  = var.system_node_pool.temporary_name_for_rotation
    tags                         = var.tags

    upgrade_settings {
      max_surge = var.system_node_pool.upgrade_max_surge
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = var.network_policy
    network_data_plane  = var.network_policy == "cilium" ? "cilium" : null
    load_balancer_sku   = "standard"
    outbound_type       = var.outbound_type
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
  }

  # Container insights, collecting with the cluster's managed identity.
  dynamic "oms_agent" {
    for_each = var.log_analytics_workspace_id == null ? [] : [1]

    content {
      log_analytics_workspace_id      = var.log_analytics_workspace_id
      msi_auth_for_monitoring_enabled = true
    }
  }

  # Mounts key vault secrets into pods through the CSI driver, kept in
  # sync when secrets rotate.
  dynamic "key_vault_secrets_provider" {
    for_each = var.enable_key_vault_secrets_provider ? [1] : []

    content {
      secret_rotation_enabled = true
    }
  }

  lifecycle {
    # Two CIDR ranges overlap exactly when they share the same network
    # address at the shorter of the two prefix lengths. The overlay and
    # service ranges must stay outside every routed range: overlapping
    # ranges break routing, and NSG rules built from them stop matching
    # the traffic they are meant to scope.
    precondition {
      condition = alltrue([
        for prefix in var.routed_address_prefixes : alltrue([
          for range in [var.pod_cidr, var.service_cidr] :
          cidrhost(format("%s/%d", split("/", prefix)[0], min(tonumber(split("/", prefix)[1]), tonumber(split("/", range)[1]))), 0) !=
          cidrhost(format("%s/%d", split("/", range)[0], min(tonumber(split("/", prefix)[1]), tonumber(split("/", range)[1]))), 0)
        ])
      ])
      error_message = "pod_cidr and service_cidr must not overlap any routed address prefix (routed_address_prefixes)."
    }
  }
}

# Additional user node pools joining the same subnet as the system
# pool.
resource "azurerm_kubernetes_cluster_node_pool" "this" {
  for_each = var.node_pools

  name                  = each.key
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  mode                  = each.value.mode
  vm_size               = each.value.vm_size
  vnet_subnet_id        = var.subnet_id
  zones                 = each.value.zones
  auto_scaling_enabled  = each.value.auto_scaling_enabled
  node_count            = each.value.node_count
  min_count             = each.value.auto_scaling_enabled ? each.value.min_count : null
  max_count             = each.value.auto_scaling_enabled ? each.value.max_count : null
  max_pods              = each.value.max_pods
  os_disk_size_gb       = each.value.os_disk_size_gb
  os_disk_type          = each.value.os_disk_type
  os_sku                = each.value.os_sku
  node_labels           = each.value.node_labels
  node_taints           = each.value.node_taints
  tags                  = var.tags

  upgrade_settings {
    max_surge = each.value.upgrade_max_surge
  }
}

# Sends the control plane's logs to Log Analytics when a workspace is
# configured. Callers that create the workspace in the same apply must
# set enable_diagnostics themselves, because the workspace ID is
# unknown until apply and cannot decide the count.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# An Azure AI Services account - the Cognitive Services resource that
# also backs Azure OpenAI - with its model deployments. Callers reach
# it with Microsoft Entra ID and RBAC through a private endpoint: the
# account's keys are disabled, so a caller holds a role
# (Cognitive Services OpenAI User to run inference, Cognitive Services
# User for the other kinds) rather than a secret.
#
# A custom subdomain is not optional here: token authentication and
# private endpoints both require the account to have one, so the module
# derives it from the account name when none is given.

locals {
  identity_type = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"

  custom_subdomain_name = coalesce(var.custom_subdomain_name, lower(var.name))

  # Whichever of the two identity variables is set. Which one it is - not
  # what is inside it - is what the lookup's cardinality turns on, and a
  # top-level object variable's presence stays known while planning even
  # when every attribute in it is an identity created in the same apply.
  customer_managed_key_identity_id = try(
    var.customer_managed_key_identity.id,
    var.customer_managed_key_external_identity.id,
    null
  )

  customer_managed_key_identity_parts = (
    local.customer_managed_key_identity_id == null
    ? null
    : provider::azurerm::parse_resource_id(local.customer_managed_key_identity_id)
  )

  # The lookup runs in the module's own provider, so it can only find an
  # identity in the deployment's subscription. This is unknown while
  # planning an identity created in the same apply, so the preconditions
  # that use it settle then rather than at plan time - which is why they
  # do not decide the lookup's cardinality.
  customer_managed_key_identity_is_local = (
    local.customer_managed_key_identity_parts == null
    ? false
    : local.customer_managed_key_identity_parts["subscription_id"] == data.azurerm_client_config.current.subscription_id
  )

  customer_managed_key_client_id = (
    var.customer_managed_key_external_identity != null
    ? var.customer_managed_key_external_identity.client_id
    : try(data.azurerm_user_assigned_identity.customer_managed_key[0].client_id, null)
  )
}

# The subscription this deployment runs in, which is the only one the
# identity lookup below can reach.
data "azurerm_client_config" "current" {}

# The account takes the key-unwrapping identity as a client ID, while
# everything else in Terraform names an identity by its resource ID.
# Reading the client ID off the identity keeps the caller to one
# identifier, so the two can never name different identities - the
# deployment principal needs read access on the identity, which it
# already has to attach it. An identity in another subscription is out
# of this provider's reach, so it carries its own client ID and skips
# the lookup entirely.
data "azurerm_user_assigned_identity" "customer_managed_key" {
  count = var.customer_managed_key_identity == null ? 0 : 1

  name                = local.customer_managed_key_identity_parts["resource_name"]
  resource_group_name = local.customer_managed_key_identity_parts["resource_group_name"]
}

resource "azurerm_cognitive_account" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = var.kind
  sku_name            = var.sku_name
  tags                = var.tags

  # Secure defaults: Microsoft Entra ID only (no account keys), no
  # public network access, and a custom subdomain so both are possible.
  # Data plane access is via a private endpoint.
  custom_subdomain_name         = local.custom_subdomain_name
  local_auth_enabled            = var.local_auth_enabled
  public_network_access_enabled = var.public_network_access_enabled

  # Data exfiltration prevention: the account may only call out to the
  # hosts listed in allowed_outbound_fqdns. Only some kinds honour it -
  # leave it off for the kinds that do not.
  outbound_network_access_restricted = var.outbound_network_access_restricted
  fqdns                              = var.allowed_outbound_fqdns

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }

  # Only meaningful while the public endpoint is open: a default-deny
  # rule set on top of it, for callers that cannot reach a private
  # endpoint.
  dynamic "network_acls" {
    for_each = var.public_network_access_enabled ? [1] : []

    content {
      default_action = var.network_acls_default_action
      ip_rules       = var.network_acls_ip_rules

      dynamic "virtual_network_rules" {
        for_each = var.network_acls_subnet_ids

        content {
          subnet_id                            = virtual_network_rules.value
          ignore_missing_vnet_service_endpoint = false
        }
      }
    }
  }

  # Customer-managed key encryption. The account is created already
  # encrypted, so the key is unwrapped by an attached user-assigned
  # identity holding wrap and unwrap on a purge-protected vault before
  # the apply - the account's system-assigned identity does not exist
  # yet at that point, which is why the variables require one.
  dynamic "customer_managed_key" {
    for_each = var.customer_managed_key == null ? [] : [var.customer_managed_key]

    content {
      key_vault_key_id   = customer_managed_key.value.key_vault_key_id
      identity_client_id = local.customer_managed_key_client_id
    }
  }

  lifecycle {
    # Each identity variable states where its identity lives, and the
    # subscription in the resource ID settles whether that was true.
    # Neither check can decide anything at plan time for an identity
    # created in the same apply, which is why the lookup's cardinality
    # rests on which variable is set instead.
    precondition {
      condition = (
        var.customer_managed_key_identity == null ||
        local.customer_managed_key_identity_is_local
      )
      error_message = "customer_managed_key_identity.id sits in another subscription, which this module cannot read a client ID from: name it with customer_managed_key_external_identity, supplying its client ID as well."
    }

    precondition {
      condition = (
        var.customer_managed_key_external_identity == null ||
        !local.customer_managed_key_identity_is_local
      )
      error_message = "customer_managed_key_external_identity.id sits in this deployment's own subscription: use customer_managed_key_identity instead, which reads the client ID off the identity rather than taking one that could name a different identity."
    }
  }
}

# The models served by the account, e.g. a chat completion deployment.
# Each deployment draws on the subscription's regional quota for its
# model and SKU, so an apply fails rather than queues when the quota
# is exhausted.
resource "azurerm_cognitive_deployment" "this" {
  for_each = var.model_deployments

  name                       = each.key
  cognitive_account_id       = azurerm_cognitive_account.this.id
  rai_policy_name            = each.value.rai_policy_name
  version_upgrade_option     = each.value.version_upgrade_option
  dynamic_throttling_enabled = each.value.dynamic_throttling_enabled

  model {
    format  = each.value.format
    name    = each.value.model_name
    version = each.value.model_version
  }

  sku {
    name     = each.value.sku_name
    tier     = each.value.sku_tier
    size     = each.value.sku_size
    family   = each.value.sku_family
    capacity = each.value.capacity
  }
}

# Sends logs and metrics to Log Analytics when a workspace is
# configured. Callers that create the workspace in the same apply must
# set enable_diagnostics themselves, because the workspace ID is unknown
# until apply and cannot decide the count.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_cognitive_account.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

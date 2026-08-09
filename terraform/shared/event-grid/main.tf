terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# An Event Grid custom topic and the subscriptions delivering its
# events. Publishers authenticate with Microsoft Entra ID and RBAC
# through a private endpoint, and deliveries leave with the topic's
# managed identity rather than a shared key, so no secret exists on
# either side of the topic.

locals {
  identity_type = length(var.user_assigned_identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"

  # Event Grid delivers with a managed identity to Service Bus queues
  # and topics, Event Hubs and Storage queues, and to nothing else. A
  # webhook is an arbitrary HTTPS endpoint with no Azure identity to
  # authorise against, and an Azure Function endpoint is authenticated
  # with the function's own key - so neither can carry a delivery
  # identity, and asking for one fails at apply time rather than at
  # plan time. delivery_identity_enabled defaults to null and resolves
  # here: on wherever the destination supports it, off where it does
  # not.
  identity_capable_subscriptions = {
    for name, subscription in var.event_subscriptions :
    name => subscription
    if subscription.webhook_url == null && subscription.azure_function_id == null
  }

  identity_subscriptions = {
    for name, subscription in local.identity_capable_subscriptions :
    name => subscription if coalesce(subscription.delivery_identity_enabled, true)
  }

  # Dead-lettering to blob storage takes an identity of its own, and
  # unlike delivery it works for every destination - a webhook
  # subscription can still dead-letter with the topic's identity. It
  # follows the delivery leg's decision unless the caller overrides it,
  # so choosing key-based delivery does not silently leave the
  # dead-letter container writable only by a principal nobody granted.
  dead_letter_identity_subscriptions = {
    for name, subscription in var.event_subscriptions :
    name => subscription
    if subscription.dead_letter_storage != null && coalesce(
      subscription.dead_letter_identity_enabled,
      contains(keys(local.identity_subscriptions), name)
    )
  }
}

resource "azurerm_eventgrid_topic" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  input_schema        = var.input_schema
  tags                = var.tags

  # Secure defaults: no shared access keys (use Microsoft Entra ID and
  # RBAC) and no public network access. Publishing is via a private
  # endpoint.
  local_auth_enabled            = var.local_auth_enabled
  public_network_access_enabled = var.public_network_access_enabled

  # A CustomEventSchema topic accepts events in the publisher's own
  # shape, so it can only be created alongside a mapping telling Event
  # Grid which of the publisher's fields carry the event type, subject
  # and data version - or constant defaults for the ones the publisher
  # does not send. Both are rejected on the two built-in schemas.
  dynamic "input_mapping_fields" {
    for_each = var.input_mapping_fields == null ? [] : [var.input_mapping_fields]

    content {
      id           = input_mapping_fields.value.id
      topic        = input_mapping_fields.value.topic
      event_time   = input_mapping_fields.value.event_time
      event_type   = input_mapping_fields.value.event_type
      subject      = input_mapping_fields.value.subject
      data_version = input_mapping_fields.value.data_version
    }
  }

  dynamic "input_mapping_default_values" {
    for_each = var.input_mapping_default_values == null ? [] : [var.input_mapping_default_values]

    content {
      event_type   = input_mapping_default_values.value.event_type
      subject      = input_mapping_default_values.value.subject
      data_version = input_mapping_default_values.value.data_version
    }
  }

  # Only meaningful while the public endpoint is open: an address
  # allow list on top of it, for publishers that cannot reach a
  # private endpoint.
  dynamic "inbound_ip_rule" {
    for_each = var.public_network_access_enabled ? var.inbound_ip_rules : []

    content {
      ip_mask = inbound_ip_rule.value.ip_mask
      action  = inbound_ip_rule.value.action
    }
  }

  identity {
    type         = local.identity_type
    identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
  }
}

# The subscriptions events are delivered to. Each names exactly one
# destination; the module validates that in the variable.
resource "azurerm_eventgrid_event_subscription" "this" {
  for_each = var.event_subscriptions

  name                  = each.key
  scope                 = azurerm_eventgrid_topic.this.id
  event_delivery_schema = each.value.event_delivery_schema
  included_event_types  = each.value.included_event_types
  labels                = each.value.labels

  eventhub_endpoint_id          = each.value.event_hub_id
  service_bus_queue_endpoint_id = each.value.service_bus_queue_id
  service_bus_topic_endpoint_id = each.value.service_bus_topic_id

  dynamic "storage_queue_endpoint" {
    for_each = each.value.storage_queue == null ? [] : [each.value.storage_queue]

    content {
      storage_account_id                    = storage_queue_endpoint.value.storage_account_id
      queue_name                            = storage_queue_endpoint.value.queue_name
      queue_message_time_to_live_in_seconds = storage_queue_endpoint.value.message_time_to_live_in_seconds
    }
  }

  dynamic "azure_function_endpoint" {
    for_each = each.value.azure_function_id == null ? [] : [each.value.azure_function_id]

    content {
      function_id                       = azure_function_endpoint.value
      max_events_per_batch              = each.value.max_events_per_batch
      preferred_batch_size_in_kilobytes = each.value.preferred_batch_size_in_kilobytes
    }
  }

  # A webhook is an arbitrary HTTPS endpoint with no Azure identity to
  # authenticate against, so it carries no delivery identity: protect
  # it with its own validation handshake and Entra ID authorisation
  # instead.
  dynamic "webhook_endpoint" {
    for_each = each.value.webhook_url == null ? [] : [each.value.webhook_url]

    content {
      url                               = webhook_endpoint.value
      max_events_per_batch              = each.value.max_events_per_batch
      preferred_batch_size_in_kilobytes = each.value.preferred_batch_size_in_kilobytes
      active_directory_tenant_id        = each.value.webhook_active_directory_tenant_id
      active_directory_app_id_or_uri    = each.value.webhook_active_directory_app_id_or_uri
    }
  }

  # Delivery with the topic's managed identity, so the destination
  # grants a principal rather than holding a key.
  dynamic "delivery_identity" {
    for_each = contains(keys(local.identity_subscriptions), each.key) ? [each.value] : []

    content {
      type                   = delivery_identity.value.user_assigned_identity_id == null ? "SystemAssigned" : "UserAssigned"
      user_assigned_identity = delivery_identity.value.user_assigned_identity_id
    }
  }

  dynamic "retry_policy" {
    for_each = each.value.max_delivery_attempts == null && each.value.event_time_to_live_minutes == null ? [] : [1]

    content {
      max_delivery_attempts = coalesce(each.value.max_delivery_attempts, 30)
      event_time_to_live    = coalesce(each.value.event_time_to_live_minutes, 1440)
    }
  }

  dynamic "subject_filter" {
    for_each = each.value.subject_begins_with == null && each.value.subject_ends_with == null ? [] : [1]

    content {
      subject_begins_with = each.value.subject_begins_with
      subject_ends_with   = each.value.subject_ends_with
      case_sensitive      = each.value.case_sensitive_subject
    }
  }

  # Events that exhaust their retries are kept rather than dropped.
  dynamic "storage_blob_dead_letter_destination" {
    for_each = each.value.dead_letter_storage == null ? [] : [each.value.dead_letter_storage]

    content {
      storage_account_id          = storage_blob_dead_letter_destination.value.storage_account_id
      storage_blob_container_name = storage_blob_dead_letter_destination.value.container_name
    }
  }

  dynamic "dead_letter_identity" {
    for_each = contains(keys(local.dead_letter_identity_subscriptions), each.key) ? [each.value] : []

    content {
      type                   = dead_letter_identity.value.user_assigned_identity_id == null ? "SystemAssigned" : "UserAssigned"
      user_assigned_identity = dead_letter_identity.value.user_assigned_identity_id
    }
  }
}

# Sends logs and metrics to Log Analytics when a workspace is
# configured. Callers that create the workspace in the same apply must
# set enable_diagnostics themselves, because the workspace ID is unknown
# until apply and cannot decide the count.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_eventgrid_topic.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

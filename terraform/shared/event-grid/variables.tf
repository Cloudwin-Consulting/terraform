variable "name" {
  description = "The name of the Event Grid topic. Must be unique within its region as it forms the topic endpoint hostname."
  type        = string

  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 50 && can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$", var.name))
    error_message = "The topic name must be 3-50 characters of letters, numbers and hyphens, starting and ending alphanumeric."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the topic is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the topic is deployed."
  type        = string
}

variable "input_schema" {
  description = "The schema publishers send events in: EventGridSchema, CloudEventSchemaV1_0 or CustomEventSchema. Fixed at creation - changing it replaces the topic."
  type        = string
  default     = "CloudEventSchemaV1_0"

  validation {
    condition     = contains(["EventGridSchema", "CloudEventSchemaV1_0", "CustomEventSchema"], var.input_schema)
    error_message = "input_schema must be EventGridSchema, CloudEventSchemaV1_0 or CustomEventSchema."
  }
}

variable "input_mapping_fields" {
  description = "Maps the publisher's own fields onto the Event Grid properties, for a CustomEventSchema topic. Each value is the name of a field in the published payload, e.g. subject = \"orderReference\". Every property left null must be covered by input_mapping_default_values instead. Rejected on the EventGridSchema and CloudEventSchemaV1_0 topics, which already know their own shape."
  type = object({
    id           = optional(string)
    topic        = optional(string)
    event_time   = optional(string)
    event_type   = optional(string)
    subject      = optional(string)
    data_version = optional(string)
  })
  default = null

  validation {
    condition     = var.input_mapping_fields == null || var.input_schema == "CustomEventSchema"
    error_message = "input_mapping_fields only applies to a CustomEventSchema topic: the built-in schemas define their own field mapping."
  }

  # Each value names a field in the published payload, so an empty
  # string names nothing. Left unchecked it would satisfy the
  # completeness rule below - which tests presence - while telling
  # Event Grid to read a field with no name.
  validation {
    condition = var.input_mapping_fields == null || alltrue([
      for field in values(var.input_mapping_fields) :
      try(trimspace(field), "unset") != ""
    ])
    error_message = "An input_mapping_fields entry cannot be blank: each value is the name of a field in the published payload, so leave the property null rather than empty to have it covered by input_mapping_default_values instead."
  }
}

variable "input_mapping_default_values" {
  description = "Constant values Event Grid stamps onto events that carry no field of their own, for a CustomEventSchema topic - e.g. data_version = \"1.0\" for a publisher that does not version its payloads. Rejected on the EventGridSchema and CloudEventSchemaV1_0 topics."
  type = object({
    event_type   = optional(string)
    subject      = optional(string)
    data_version = optional(string)
  })
  default = null

  validation {
    condition     = var.input_mapping_default_values == null || var.input_schema == "CustomEventSchema"
    error_message = "input_mapping_default_values only applies to a CustomEventSchema topic: the built-in schemas define their own field mapping."
  }

  # The completeness check lives here rather than on input_schema so the
  # validations reference each other in one direction only - Terraform
  # rejects a cycle between them.
  #
  # A blank string counts as absent on both sides: it names no field and
  # supplies no constant, so treating it as coverage would let an
  # incomplete mapping through the one rule meant to catch exactly that.
  validation {
    condition = var.input_schema != "CustomEventSchema" || (
      (try(trimspace(var.input_mapping_fields.event_type), "") != "" || try(trimspace(var.input_mapping_default_values.event_type), "") != "") &&
      (try(trimspace(var.input_mapping_fields.subject), "") != "" || try(trimspace(var.input_mapping_default_values.subject), "") != "") &&
      (try(trimspace(var.input_mapping_fields.data_version), "") != "" || try(trimspace(var.input_mapping_default_values.data_version), "") != "")
    )
    error_message = "A CustomEventSchema topic needs event_type, subject and data_version each either mapped onto a published field in input_mapping_fields or given a constant in input_mapping_default_values: Event Grid cannot read a custom payload without that mapping."
  }
}

variable "local_auth_enabled" {
  description = "Whether publishers may authenticate with the topic's access keys. Keep disabled so Microsoft Entra ID and RBAC are the only publishing path."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Whether the topic is reachable over the public internet. Keep disabled and publish to it through a private endpoint."
  type        = bool
  default     = false
}

variable "inbound_ip_rules" {
  description = "Address ranges allowed to publish while the public endpoint is open, in evaluation order. Ignored when public_network_access_enabled is false."
  type = list(object({
    ip_mask = string
    action  = optional(string, "Allow")
  }))
  default = []

  validation {
    condition     = alltrue([for rule in var.inbound_ip_rules : rule.action == "Allow"])
    error_message = "Event Grid inbound IP rules only support the Allow action: everything not listed is denied."
  }
}

variable "user_assigned_identity_ids" {
  description = "User-assigned identity IDs attached to the topic alongside its system-assigned identity, e.g. an identity a destination already trusts. Leave empty for the system-assigned identity alone."
  type        = list(string)
  default     = []
}

variable "event_subscriptions" {
  description = <<-EOT
    Subscriptions delivering the topic's events, keyed by subscription name. Each subscription names exactly one destination: event_hub_id, service_bus_queue_id, service_bus_topic_id, storage_queue, azure_function_id or webhook_url.

    Deliveries to a Service Bus queue or topic, an Event Hub or a Storage queue carry the topic's system-assigned managed identity by default, so the destination grants that principal a role instead of holding a key; set user_assigned_identity_id to use one of user_assigned_identity_ids instead, or delivery_identity_enabled = false to fall back to key-based delivery. That identity serves whichever legs use one - delivery, dead-lettering, or only the second of those when delivery falls back to a key.

    Event Grid supports identity-based delivery to those three destinations only. A webhook is an arbitrary HTTPS endpoint with no Azure identity to authorise against - secure it with webhook_active_directory_tenant_id and webhook_active_directory_app_id_or_uri so the handler can authorise the caller - and an Azure Function endpoint is authenticated with the function's own key. Both are therefore delivered to without an identity, whatever delivery_identity_enabled is left at.

    dead_letter_storage keeps events that exhaust their retries in a blob container. Those writes follow the delivery leg's choice of identity unless dead_letter_identity_enabled says otherwise: a subscription delivering with a key dead-letters with one too, so the container does not end up writable only by a principal nobody granted. Dead-lettering with an identity works for every destination, so a webhook or Azure Function subscription can set it true even though its delivery cannot use one - grant that principal Storage Blob Data Contributor on the account.
  EOT

  type = map(object({
    event_delivery_schema = optional(string, "CloudEventSchemaV1_0")
    included_event_types  = optional(list(string))
    labels                = optional(list(string))

    subject_begins_with    = optional(string)
    subject_ends_with      = optional(string)
    case_sensitive_subject = optional(bool, false)

    event_hub_id         = optional(string)
    service_bus_queue_id = optional(string)
    service_bus_topic_id = optional(string)
    azure_function_id    = optional(string)
    webhook_url          = optional(string)
    storage_queue = optional(object({
      storage_account_id              = string
      queue_name                      = string
      message_time_to_live_in_seconds = optional(number, 604800)
    }))

    delivery_identity_enabled    = optional(bool)
    dead_letter_identity_enabled = optional(bool)
    user_assigned_identity_id    = optional(string)

    webhook_active_directory_tenant_id     = optional(string)
    webhook_active_directory_app_id_or_uri = optional(string)

    max_events_per_batch              = optional(number)
    preferred_batch_size_in_kilobytes = optional(number)

    max_delivery_attempts      = optional(number, 30)
    event_time_to_live_minutes = optional(number, 1440)

    dead_letter_storage = optional(object({
      storage_account_id = string
      container_name     = string
    }))
  }))

  default = {}

  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      length(compact([
        subscription.event_hub_id,
        subscription.service_bus_queue_id,
        subscription.service_bus_topic_id,
        subscription.azure_function_id,
        subscription.webhook_url,
        subscription.storage_queue == null ? null : subscription.storage_queue.queue_name,
      ])) == 1
    ])
    error_message = "Every event subscription must name exactly one destination: event_hub_id, service_bus_queue_id, service_bus_topic_id, azure_function_id, webhook_url or storage_queue."
  }

  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      contains(["EventGridSchema", "CloudEventSchemaV1_0", "CustomInputSchema"], subscription.event_delivery_schema)
    ])
    error_message = "event_delivery_schema must be EventGridSchema, CloudEventSchemaV1_0 or CustomInputSchema."
  }

  # CloudEvents carries extension attributes the Event Grid schema has
  # nowhere to put, so that one pairing of input and output schema is
  # unsupported - and this module's default input schema is CloudEvents,
  # which makes it the easy mistake to make.
  validation {
    condition = var.input_schema != "CloudEventSchemaV1_0" || alltrue([
      for name, subscription in var.event_subscriptions :
      subscription.event_delivery_schema != "EventGridSchema"
    ])
    error_message = "A CloudEventSchemaV1_0 topic cannot deliver in the EventGridSchema: CloudEvents supports extension attributes the Event Grid schema does not carry. Deliver as CloudEventSchemaV1_0, or publish to the topic in the EventGridSchema instead."
  }

  # Delivering as CustomInputSchema means keeping the shape the topic
  # was published in, which only a CustomEventSchema topic has.
  validation {
    condition = var.input_schema == "CustomEventSchema" || alltrue([
      for name, subscription in var.event_subscriptions :
      subscription.event_delivery_schema != "CustomInputSchema"
    ])
    error_message = "event_delivery_schema = CustomInputSchema needs a CustomEventSchema topic: it delivers events in the custom shape they were published in, and a topic on one of the built-in schemas has no such shape to preserve."
  }

  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      subscription.webhook_url == null || startswith(subscription.webhook_url, "https://")
    ])
    error_message = "A webhook destination must be an https:// URL: Event Grid will not deliver events in the clear."
  }

  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      subscription.user_assigned_identity_id == null ||
      coalesce(subscription.delivery_identity_enabled, true) ||
      coalesce(subscription.dead_letter_identity_enabled, false)
    ])
    error_message = "user_assigned_identity_id has nothing to act on: it names the identity for identity-based delivery and dead-lettering, and this subscription has turned both off."
  }

  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      subscription.delivery_identity_enabled != true || (subscription.webhook_url == null && subscription.azure_function_id == null)
    ])
    error_message = "delivery_identity_enabled cannot be true for a webhook or Azure Function destination: Event Grid delivers with a managed identity to Service Bus queues and topics, Event Hubs and Storage queues only. Leave it unset for those destinations."
  }

  # Batching is a property of the push destinations Event Grid posts
  # events to. The queue and streaming destinations take one event per
  # message, so these two settings have nowhere to go there - and a
  # subscription that quietly ignored them would batch nothing while
  # its configuration said otherwise.
  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      (subscription.max_events_per_batch == null && subscription.preferred_batch_size_in_kilobytes == null) ||
      subscription.azure_function_id != null || subscription.webhook_url != null
    ])
    error_message = "max_events_per_batch and preferred_batch_size_in_kilobytes apply to Azure Function and webhook destinations only: a Service Bus queue or topic, an Event Hub and a Storage queue each take one event per message, so there is no batch to size. Leave both unset for those destinations."
  }

  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      subscription.max_events_per_batch == null || (
        subscription.max_events_per_batch >= 1 &&
        subscription.max_events_per_batch <= 5000 &&
        floor(subscription.max_events_per_batch) == subscription.max_events_per_batch
      )
    ])
    error_message = "max_events_per_batch must be a whole number between 1 and 5000: it counts events, and Event Grid never exceeds the number given."
  }

  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      subscription.preferred_batch_size_in_kilobytes == null || (
        subscription.preferred_batch_size_in_kilobytes >= 1 &&
        subscription.preferred_batch_size_in_kilobytes <= 1024 &&
        floor(subscription.preferred_batch_size_in_kilobytes) == subscription.preferred_batch_size_in_kilobytes
      )
    ])
    error_message = "preferred_batch_size_in_kilobytes must be a whole number between 1 and 1024. It is a target rather than a hard ceiling - a single event larger than it is still delivered, in a batch of its own."
  }

  # Zero and every other negative are rejected by the service; -1 is
  # carved out to mean the message never expires.
  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      subscription.storage_queue == null || (
        subscription.storage_queue.message_time_to_live_in_seconds == null ||
        (
          floor(subscription.storage_queue.message_time_to_live_in_seconds) == subscription.storage_queue.message_time_to_live_in_seconds &&
          (
            subscription.storage_queue.message_time_to_live_in_seconds >= 1 ||
            subscription.storage_queue.message_time_to_live_in_seconds == -1
          )
        )
      )
    ])
    error_message = "storage_queue.message_time_to_live_in_seconds must be a whole number of at least 1 second, or -1 for messages that never expire: Event Grid rejects zero and every other negative value."
  }

  # Terraform's map keys are distinct case-sensitively; Azure Resource
  # Manager compares names case-insensitively. Both entries plan, and
  # the second to apply collides with the first.
  validation {
    condition     = length(distinct([for name, subscription in var.event_subscriptions : lower(name)])) == length(var.event_subscriptions)
    error_message = "Event subscription names must be unique on the topic, ignoring case: Azure Resource Manager compares resource names case-insensitively, so two keys differing only in capitalisation name the same subscription."
  }

  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      subscription.user_assigned_identity_id == null ||
      (subscription.webhook_url == null && subscription.azure_function_id == null) ||
      coalesce(subscription.dead_letter_identity_enabled, false)
    ])
    error_message = "user_assigned_identity_id cannot be set for a webhook or Azure Function destination unless dead_letter_identity_enabled is true: neither is delivered to with a managed identity, though either can dead-letter with one."
  }

  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      subscription.user_assigned_identity_id == null || contains(var.user_assigned_identity_ids, coalesce(subscription.user_assigned_identity_id, "unset"))
    ])
    error_message = "Every user_assigned_identity_id must be one of the topic's user_assigned_identity_ids: Event Grid delivers with an identity the topic has attached, not with one it never joined."
  }

  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      subscription.dead_letter_identity_enabled != true || subscription.dead_letter_storage != null
    ])
    error_message = "dead_letter_identity_enabled = true needs dead_letter_storage: there is nothing to write with that identity without a dead-letter container. Setting it false is always fine - it asks for no identity block at all."
  }

  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      (subscription.webhook_active_directory_tenant_id == null) == (subscription.webhook_active_directory_app_id_or_uri == null)
    ])
    error_message = "A webhook's Microsoft Entra ID authentication needs webhook_active_directory_tenant_id and webhook_active_directory_app_id_or_uri together: one without the other is an incomplete configuration Event Grid rejects."
  }

  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      subscription.webhook_url != null || (subscription.webhook_active_directory_tenant_id == null && subscription.webhook_active_directory_app_id_or_uri == null)
    ])
    error_message = "The webhook_active_directory_* inputs only apply to a webhook destination: the other destinations are authenticated with a managed identity or a key."
  }

  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      subscription.max_delivery_attempts == null || (
        subscription.max_delivery_attempts >= 1 &&
        subscription.max_delivery_attempts <= 30 &&
        floor(subscription.max_delivery_attempts) == subscription.max_delivery_attempts
      )
    ])
    error_message = "max_delivery_attempts must be a whole number between 1 and 30."
  }

  validation {
    condition = alltrue([
      for name, subscription in var.event_subscriptions :
      subscription.event_time_to_live_minutes == null || (
        subscription.event_time_to_live_minutes >= 1 &&
        subscription.event_time_to_live_minutes <= 1440 &&
        floor(subscription.event_time_to_live_minutes) == subscription.event_time_to_live_minutes
      )
    ])
    error_message = "event_time_to_live_minutes must be a whole number between 1 and 1440 (24 hours, the Event Grid maximum)."
  }
}

variable "log_analytics_workspace_id" {
  description = "The ID of a Log Analytics workspace to send diagnostics to. Leave null to skip diagnostics."
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

variable "tags" {
  description = "Tags applied to the topic."
  type        = map(string)
  default     = {}
}

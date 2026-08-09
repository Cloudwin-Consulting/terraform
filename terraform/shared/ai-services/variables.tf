variable "name" {
  description = "The name of the AI Services account. Must be unique within its region, and forms the default custom subdomain."
  type        = string

  validation {
    condition     = length(var.name) >= 2 && length(var.name) <= 64 && can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$", var.name))
    error_message = "The account name must be 2-64 characters of letters, numbers and hyphens, starting and ending alphanumeric."
  }
}

variable "resource_group_name" {
  description = "The resource group into which the account is deployed."
  type        = string
}

variable "location" {
  description = "The Azure location into which the account is deployed. Model availability is regional - check the model is served in this region before deploying it."
  type        = string
}

variable "kind" {
  description = "The kind of account: AIServices for the multi-service account, OpenAI for an Azure OpenAI-only account, or a single-service kind such as ComputerVision, TextAnalytics, SpeechServices, FormRecognizer or ContentSafety."
  type        = string
  default     = "AIServices"

  validation {
    condition = contains([
      "AIServices",
      "OpenAI",
      "CognitiveServices",
      "ComputerVision",
      "ContentSafety",
      "CustomVision.Prediction",
      "CustomVision.Training",
      "FormRecognizer",
      "Face",
      "HealthInsights",
      "ImmersiveReader",
      "LanguageAuthoring",
      "SpeechServices",
      "TextAnalytics",
      "TextTranslation",
    ], var.kind)
    error_message = "kind must be one of the supported Azure AI Services kinds, e.g. AIServices, OpenAI, ComputerVision, SpeechServices or TextAnalytics."
  }
}

variable "sku_name" {
  description = "The SKU of the account. S0 is the standard pay-as-you-go tier; F0 is the free tier, which most kinds allow only one of per subscription and the OpenAI kind does not offer at all."
  type        = string
  default     = "S0"

  validation {
    condition     = var.kind != "OpenAI" || var.sku_name != "F0"
    error_message = "The OpenAI kind has no free tier: use S0 for an Azure OpenAI account, or the AIServices kind if a free multi-service account is what is wanted."
  }
}

variable "custom_subdomain_name" {
  description = "The custom subdomain forming the account's endpoint, https://<subdomain>.cognitiveservices.azure.com (or .openai.azure.com). Defaults to the account name in lower case. Required for token authentication and private endpoints, so the module always sets one - changing it later replaces the account."
  type        = string
  default     = null

  validation {
    condition     = var.custom_subdomain_name == null || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", coalesce(var.custom_subdomain_name, "placeholder")))
    error_message = "custom_subdomain_name must be lower-case letters, numbers and hyphens, starting and ending alphanumeric."
  }

  validation {
    condition     = var.custom_subdomain_name == null || (length(coalesce(var.custom_subdomain_name, "placeholder")) >= 2 && length(coalesce(var.custom_subdomain_name, "placeholder")) <= 64)
    error_message = "custom_subdomain_name must be 2-64 characters, the same bounds as the account name it defaults to."
  }
}

variable "local_auth_enabled" {
  description = "Whether callers may authenticate with the account's keys. Keep disabled so Microsoft Entra ID and RBAC are the only path - callers hold Cognitive Services OpenAI User or Cognitive Services User instead of a key."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Whether the account is reachable over the public internet. Keep disabled and call it through a private endpoint (the account subresource, resolved by privatelink.cognitiveservices.azure.com, privatelink.openai.azure.com and privatelink.services.ai.azure.com)."
  type        = bool
  default     = false
}

variable "outbound_network_access_restricted" {
  description = "Whether the account may only call out to allowed_outbound_fqdns. Data exfiltration prevention for the kinds that support it (Azure OpenAI 'on your data' and the vision and language services that fetch caller-supplied URLs); leave false for kinds that do not."
  type        = bool
  default     = false
}

variable "allowed_outbound_fqdns" {
  description = "Hostnames the account may call out to when outbound_network_access_restricted is true. An empty list with the restriction on blocks all outbound calls."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.allowed_outbound_fqdns) == 0 || var.outbound_network_access_restricted
    error_message = "allowed_outbound_fqdns only applies when outbound_network_access_restricted is true."
  }
}

variable "network_acls_default_action" {
  description = "What happens to public traffic matching no rule while the public endpoint is open: Deny or Allow. Ignored when public_network_access_enabled is false."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.network_acls_default_action)
    error_message = "network_acls_default_action must be Allow or Deny."
  }
}

variable "network_acls_ip_rules" {
  description = "Public addresses or CIDR ranges allowed while the public endpoint is open. Ignored when public_network_access_enabled is false."
  type        = list(string)
  default     = []
}

variable "network_acls_subnet_ids" {
  description = "Subnet IDs allowed while the public endpoint is open. Each subnet needs the Microsoft.CognitiveServices service endpoint. Ignored when public_network_access_enabled is false."
  type        = list(string)
  default     = []
}

variable "user_assigned_identity_ids" {
  description = "User-assigned identity IDs attached to the account alongside its system-assigned identity, e.g. one holding the key vault key for customer-managed encryption. Leave empty for the system-assigned identity alone."
  type        = list(string)
  default     = []
}

variable "customer_managed_key" {
  description = <<-EOT
    Encrypts the account with a customer-managed key held in a purge-protected vault. Leave null for platform-managed keys.

    The key must be unwrapped by a user-assigned identity - customer_managed_key_identity for one in this subscription, customer_managed_key_external_identity for one elsewhere - granted Key Vault Crypto Service Encryption User on the vault before the apply.

    The account's own system-assigned identity cannot do it on a first deployment: that principal does not exist until the account has been created, so nothing can have granted it access to the vault beforehand, and the account is created already encrypted. A user-assigned identity exists ahead of the account and can be granted the role in advance, which is also what the sibling data factory and Automation account modules require.
  EOT

  type = object({
    key_vault_key_id = string
  })
  default = null
}

variable "customer_managed_key_identity" {
  description = <<-EOT
    A user-assigned identity in this deployment's subscription that unwraps the customer-managed key, instead of the account's system-assigned one. Its id must be one of user_assigned_identity_ids, so the account is known to have attached it.

    The service takes that identity as a client ID rather than a resource ID, and the module reads it off the identity itself, so the two identifiers cannot disagree. An identity in another subscription cannot be read from here - name it with customer_managed_key_external_identity instead, which the account's precondition asks for if this one turns out to be remote.
  EOT

  type = object({
    id = string
  })
  default = null

  validation {
    condition     = var.customer_managed_key_identity == null || contains(var.user_assigned_identity_ids, try(var.customer_managed_key_identity.id, ""))
    error_message = "customer_managed_key_identity.id must be one of user_assigned_identity_ids: the account unwraps the key with an identity it has attached, not with one it never joined."
  }

  validation {
    condition     = var.customer_managed_key_identity == null || var.customer_managed_key != null
    error_message = "customer_managed_key_identity has nothing to unwrap without customer_managed_key: set the key as well, or leave the identity null."
  }
}

variable "customer_managed_key_external_identity" {
  description = <<-EOT
    A user-assigned identity in another subscription that unwraps the customer-managed key. Both identifiers are given because this module's provider cannot read an identity outside the deployment's subscription: id is the resource ID, which must still be one of user_assigned_identity_ids, and client_id is the form the service takes.

    Which of the two identity variables is set - rather than what is inside either - is what decides whether the module looks the client ID up. That keeps the decision knowable while planning, so an identity created in the same apply works on either path; a single variable with an optional client_id could not, because a computed client ID would leave the choice unresolved until apply.
  EOT

  type = object({
    id        = string
    client_id = string
  })
  default = null

  validation {
    condition     = var.customer_managed_key_external_identity == null || contains(var.user_assigned_identity_ids, try(var.customer_managed_key_external_identity.id, ""))
    error_message = "customer_managed_key_external_identity.id must be one of user_assigned_identity_ids: the account unwraps the key with an identity it has attached, not with one it never joined."
  }

  validation {
    condition     = var.customer_managed_key_external_identity == null || var.customer_managed_key != null
    error_message = "customer_managed_key_external_identity has nothing to unwrap without customer_managed_key: set the key as well, or leave the identity null."
  }

  validation {
    condition     = var.customer_managed_key_external_identity == null || var.customer_managed_key_identity == null
    error_message = "One identity unwraps the key: set customer_managed_key_identity for one in this subscription, or customer_managed_key_external_identity for one elsewhere, not both."
  }

  # The account is created already encrypted, so whichever identity
  # unwraps the key has to hold the vault role before that request is
  # sent. A system-assigned identity cannot: it comes into existence
  # with the account, so there is no earlier moment at which to grant
  # it anything.
  #
  # This check lives here rather than on customer_managed_key because
  # that variable is referenced by both identity variables' own rules -
  # putting it there would close the loop and Terraform rejects a cycle
  # between validations. The references run external -> identity -> key
  # in one direction only.
  validation {
    condition = var.customer_managed_key == null || (
      var.customer_managed_key_identity != null ||
      var.customer_managed_key_external_identity != null
    )
    error_message = "customer_managed_key needs customer_managed_key_identity or customer_managed_key_external_identity: the account is created already encrypted, and its system-assigned identity does not exist until that create has succeeded, so it cannot have been granted Key Vault Crypto Service Encryption User beforehand. Attach a user-assigned identity, grant it on the vault, and name it here."
  }
}

variable "model_deployments" {
  description = <<-EOT
    Models served by the account, keyed by deployment name - the name callers pass as the deployment in their requests.

    sku_name picks how capacity is bought: Standard (regional pay-as-you-go), GlobalStandard (routed to any region with capacity), DataZoneStandard (routed within a data residency boundary) or ProvisionedManaged (reserved throughput). capacity is thousands of tokens per minute for the Standard families and provisioned throughput units for ProvisionedManaged.

    version_upgrade_option controls what happens when the model's version retires: OnceNewDefaultVersionAvailable follows the service default, OnceCurrentVersionExpired only moves when the pinned version expires, and NoAutoUpgrade never moves - which fails calls once the version retires.
  EOT

  type = map(object({
    model_name    = string
    model_version = optional(string)
    format        = optional(string, "OpenAI")

    sku_name   = optional(string, "GlobalStandard")
    sku_tier   = optional(string)
    sku_size   = optional(string)
    sku_family = optional(string)
    capacity   = optional(number, 1)

    rai_policy_name            = optional(string)
    version_upgrade_option     = optional(string, "OnceCurrentVersionExpired")
    dynamic_throttling_enabled = optional(bool)
  }))

  default = {}

  validation {
    condition     = length(var.model_deployments) == 0 || contains(["AIServices", "OpenAI"], var.kind)
    error_message = "model_deployments require the AIServices or OpenAI kind: the single-service kinds (ComputerVision, SpeechServices, TextAnalytics, ...) serve pre-built endpoints and have no model deployment API, so the deployments would fail at apply."
  }

  validation {
    condition = alltrue([
      for name, deployment in var.model_deployments :
      contains(["Standard", "GlobalStandard", "GlobalBatch", "DataZoneStandard", "DataZoneBatch", "ProvisionedManaged", "GlobalProvisionedManaged"], deployment.sku_name)
    ])
    error_message = "A deployment's sku_name must be Standard, GlobalStandard, GlobalBatch, DataZoneStandard, DataZoneBatch, ProvisionedManaged or GlobalProvisionedManaged."
  }

  validation {
    condition = alltrue([
      for name, deployment in var.model_deployments :
      contains(["OnceNewDefaultVersionAvailable", "OnceCurrentVersionExpired", "NoAutoUpgrade"], deployment.version_upgrade_option)
    ])
    error_message = "version_upgrade_option must be OnceNewDefaultVersionAvailable, OnceCurrentVersionExpired or NoAutoUpgrade."
  }

  validation {
    condition = alltrue([
      for name, deployment in var.model_deployments :
      deployment.capacity == null || (deployment.capacity > 0 && floor(deployment.capacity) == deployment.capacity)
    ])
    error_message = "A deployment's capacity must be a whole number greater than zero: it counts thousands of tokens per minute on the Standard families and provisioned throughput units on ProvisionedManaged, neither of which is divisible."
  }

  # Terraform's map keys are distinct case-sensitively; Azure Resource
  # Manager compares names case-insensitively. Both entries plan, and
  # the second to apply collides with the first.
  validation {
    condition     = length(distinct([for name, deployment in var.model_deployments : lower(name)])) == length(var.model_deployments)
    error_message = "Model deployment names must be unique on the account, ignoring case: Azure Resource Manager compares resource names case-insensitively, so two keys differing only in capitalisation name the same deployment - and the name is what callers pass as the deployment in their requests."
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
  description = "Tags applied to the account."
  type        = map(string)
  default     = {}
}

variable "deployment_subscription_id" {
  description = "The Azure subscription into which resources will be deployed."
  type        = string
}

variable "deployment_location" {
  description = "The Azure location into which resources will be deployed. Front Door itself is global; the location applies to the resource group."
  type        = string
}

variable "deployment_name" {
  description = "The name of the workload being deployed, without the environment (e.g. app1). Every resource name is derived from it and environment together - rg-<deployment_name>-<environment> for the resource group, <abbreviation>-<deployment_name>-<environment> for the resources in it - so the pair must be unique across all stacks and environments: a workload name reused in the same environment derives the same resource group name and clashes on globally unique names."
  type        = string
}

variable "environment" {
  description = "The environment this deployment targets (e.g. rd, dev, qa, prod). It is appended to deployment_name to derive every resource name, and to the upstream workload names this stack looks its dependencies up by, so a single configuration targets any environment by changing this value alone."
  type        = string
}

variable "front_door_name" {
  description = "The name of the Front Door profile. Defaults to afd-<deployment_name>-<environment>."
  type        = string
  default     = null
}

variable "front_door_sku" {
  description = "The SKU of the profile. Premium_AzureFrontDoor is required for private link origins, which is how a real origin keeps public network access disabled; Standard_AzureFrontDoor is enough for the public placeholder origins this example ships with."
  type        = string
  default     = "Premium_AzureFrontDoor"

  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.front_door_sku)
    error_message = "front_door_sku must be Standard_AzureFrontDoor or Premium_AzureFrontDoor."
  }
}

variable "front_door_response_timeout_seconds" {
  description = "Seconds Front Door waits for a response from an origin. Between 16 and 240."
  type        = number
  default     = 60

  validation {
    condition = (
      var.front_door_response_timeout_seconds >= 16 &&
      var.front_door_response_timeout_seconds <= 240 &&
      floor(var.front_door_response_timeout_seconds) == var.front_door_response_timeout_seconds
    )
    error_message = "front_door_response_timeout_seconds must be a whole number between 16 and 240: Front Door accepts no origin response timeout outside those bounds."
  }
}

variable "front_door_endpoints" {
  description = <<-EOT
    Endpoints on the profile, keyed by a short role name (primary, secondary, ...). Each entry creates an endpoint with its own origin group, origin and route.

    The defaults point at dummy example.com hostnames, so the profile deploys with every origin unhealthy - replace origin_host_name with a real origin to make it serve. endpoint_name defaults to fde-<deployment_name>-<environment>-<key> and must be globally unique, as it forms the <endpoint>.z01.azurefd.net hostname.

    private_link reaches the origin over Private Link, which is what lets a real origin keep public network access disabled - target_id is the origin resource, target_type its subresource (sites for a web app, blob for a storage account; null for a private link service, which publishes a load balancer rather than a subresource) and location the origin's region. It needs the Premium SKU, and the pending private endpoint connection on the origin must be approved after the first deployment. Leave it null for a public origin, as the placeholders are.
  EOT

  type = map(object({
    endpoint_name                  = optional(string)
    origin_host_name               = string
    origin_http_port               = optional(number, 80)
    origin_https_port              = optional(number, 443)
    origin_forwarding_protocol     = optional(string, "HttpsOnly")
    health_probe_path              = optional(string, "/")
    health_probe_protocol          = optional(string, "Https")
    certificate_name_check_enabled = optional(bool, false)

    private_link = optional(object({
      target_id   = string
      target_type = optional(string)
      location    = string
    }))
  }))

  default = {
    primary = {
      origin_host_name  = "placeholder-primary.example.com"
      health_probe_path = "/healthz"
    }

    secondary = {
      origin_host_name  = "placeholder-secondary.example.com"
      health_probe_path = "/healthz"
    }
  }

  # The map's keys only have to be unique among themselves. What has to
  # be unique in Azure is the name each entry resolves to, which an
  # explicit endpoint_name can collide with - including against another
  # entry's derived default. Names are compared lower-cased because they
  # become DNS hostnames, which do not distinguish case.
  validation {
    condition = length(distinct([
      for name, endpoint in var.front_door_endpoints :
      lower(coalesce(endpoint.endpoint_name, "fde-${var.deployment_name}-${var.environment}-${name}"))
    ])) == length(var.front_door_endpoints)
    error_message = "Two endpoints resolve to the same name, ignoring case: an endpoint_name may not repeat another entry's endpoint_name or the fde-<deployment_name>-<environment>-<key> default another entry falls back to, and the names form DNS hostnames that are not case-sensitive."
  }

  validation {
    condition = alltrue([
      for name, endpoint in var.front_door_endpoints :
      contains(["HttpsOnly", "HttpOnly", "MatchRequest"], endpoint.origin_forwarding_protocol)
    ])
    error_message = "origin_forwarding_protocol must be HttpsOnly, HttpOnly or MatchRequest."
  }

  validation {
    condition = alltrue([
      for name, endpoint in var.front_door_endpoints :
      contains(["Http", "Https"], endpoint.health_probe_protocol)
    ])
    error_message = "health_probe_protocol must be Http or Https."
  }

  validation {
    condition = alltrue([
      for name, endpoint in var.front_door_endpoints :
      alltrue([
        for port in [endpoint.origin_http_port, endpoint.origin_https_port] :
        port >= 1 && port <= 65535 && floor(port) == port
      ])
    ])
    error_message = "origin_http_port and origin_https_port must each be a whole TCP port number from 1 to 65535."
  }

  # Private Link origins are a Premium feature. Standard accepts the
  # profile and then rejects the origin, so the SKU is worth catching
  # here rather than partway through the apply.
  validation {
    condition = var.front_door_sku == "Premium_AzureFrontDoor" || alltrue([
      for name, endpoint in var.front_door_endpoints :
      endpoint.private_link == null
    ])
    error_message = "A private_link origin needs front_door_sku = Premium_AzureFrontDoor: the Standard SKU reaches origins over the public internet only."
  }
}

variable "enable_diagnostics" {
  description = "Whether to send the profile's access, WAF and health probe logs to the monitoring spoke's Log Analytics workspace. Requires the monitoring spoke to be deployed with enable_log_analytics."
  type        = bool
  default     = false
}

variable "monitoring_subscription_id" {
  description = "The Azure subscription the monitoring spoke is deployed into, when it differs from this deployment's subscription. Leave null when they share a subscription. This stack's monitoring lookup runs against it; diagnostics reference the workspace by ID, which spans subscriptions."
  type        = string
  default     = null
}

variable "monitoring_deployment_name" {
  description = "The workload name of the monitoring spoke this stack sends diagnostics to, without the environment (e.g. monitoring-spoke). Its resource group and Log Analytics workspace are looked up as rg-<monitoring_deployment_name>-<environment> and log-<monitoring_deployment_name>-<environment>, so it must match the monitoring stack's deployment_name and the monitoring spoke must be deployed into the same environment. Only used when enable_diagnostics is true."
  type        = string
  default     = "monitoring-spoke"
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
  default     = "CloudEngineering"

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
  default     = "EntryPoint"

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

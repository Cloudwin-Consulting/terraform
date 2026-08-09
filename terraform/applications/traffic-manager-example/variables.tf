variable "deployment_subscription_id" {
  description = "The Azure subscription into which resources will be deployed."
  type        = string
}

variable "deployment_location" {
  description = "The Azure location into which resources will be deployed. Traffic Manager itself is global; the location applies to the resource group."
  type        = string
}

variable "deployment_name" {
  description = "The name of the workload being deployed, without the environment (e.g. app1). Every resource name is derived from it and environment together - rg-<deployment_name>-<environment> for the resource group, <abbreviation>-<deployment_name>-<environment> for the resources in it - so the pair must be unique across all stacks and environments: a workload name reused in the same environment derives the same resource group name and clashes on globally unique names."
  type        = string
}

variable "environment" {
  description = "The environment this deployment targets (e.g. rd, dev, qa, prod). It is appended to deployment_name to derive every resource name, so a single configuration targets any environment by changing this value alone."
  type        = string
}

variable "traffic_manager_dns_name" {
  description = "The globally unique relative DNS name of the profile, forming <name>.trafficmanager.net. Defaults to <deployment_name>-<environment>; override it when the name is taken."
  type        = string
  default     = null
}

variable "dns_ttl" {
  description = "The TTL of the profile's DNS responses in seconds. Lower values fail traffic over sooner and cost more queries."
  type        = number
  default     = 60

  validation {
    condition     = var.dns_ttl >= 0 && var.dns_ttl <= 2147483647 && floor(var.dns_ttl) == var.dns_ttl
    error_message = "dns_ttl must be a whole, non-negative number of seconds: a DNS record's time to live is counted in whole seconds."
  }
}

variable "traffic_routing_method" {
  description = "How traffic is routed across the endpoints: Priority (first healthy endpoint), Weighted (share of queries), Performance (lowest latency from the client) or MultiValue (all healthy endpoints in one answer)."
  type        = string
  default     = "Priority"

  validation {
    condition     = contains(["Priority", "Weighted", "Performance", "MultiValue"], var.traffic_routing_method)
    error_message = "traffic_routing_method must be Priority, Weighted, Performance or MultiValue."
  }
}

variable "monitor_protocol" {
  description = "The protocol health probes use: HTTPS, HTTP or TCP. Probes come from the public internet."
  type        = string
  default     = "HTTPS"

  validation {
    condition     = contains(["HTTP", "HTTPS", "TCP"], var.monitor_protocol)
    error_message = "monitor_protocol must be HTTP, HTTPS or TCP."
  }
}

variable "monitor_port" {
  description = "The port health probes target."
  type        = number
  default     = 443

  validation {
    condition     = var.monitor_port >= 1 && var.monitor_port <= 65535 && floor(var.monitor_port) == var.monitor_port
    error_message = "monitor_port must be a whole TCP port number from 1 to 65535."
  }
}

variable "monitor_path" {
  description = "The path health probes request. Ignored for TCP probes."
  type        = string
  default     = "/"
}

variable "external_endpoints" {
  description = <<-EOT
    The endpoints traffic is routed across. The defaults are dummy example.com hostnames served without probing, so the profile deploys and answers queries on its own - replace each target with a real hostname to make it route somewhere.

    priority orders endpoints for Priority routing (1 first, lowest wins), weight shares queries for Weighted routing, and location is the Azure region an endpoint sits in, which Performance routing needs. always_serve_enabled = true bypasses probing, which is required for an endpoint that is only reachable privately - and for a placeholder that is not reachable at all.
  EOT

  type = list(object({
    name                 = string
    target               = string
    location             = optional(string)
    priority             = optional(number)
    weight               = optional(number)
    always_serve_enabled = optional(bool, false)
  }))

  default = [
    {
      name                 = "primary"
      target               = "placeholder-primary.example.com"
      priority             = 1
      weight               = 100
      always_serve_enabled = true
    },
    {
      name                 = "secondary"
      target               = "placeholder-secondary.example.com"
      priority             = 2
      weight               = 100
      always_serve_enabled = true
    },
  ]

  validation {
    condition     = length(var.external_endpoints) > 0
    error_message = "A profile with no endpoints answers nothing: define at least one external endpoint."
  }

  # Azure resource names are compared without regard to case, so
  # "primary" and "Primary" are one name to the profile and two to the
  # for_each that creates them.
  validation {
    condition     = length(distinct([for endpoint in var.external_endpoints : lower(endpoint.name)])) == length(var.external_endpoints)
    error_message = "Endpoint names must be unique within the profile, ignoring case: two endpoints differing only in capitalisation are the same name to Azure."
  }

  validation {
    condition = var.traffic_routing_method != "Priority" || alltrue([
      for endpoint in var.external_endpoints : endpoint.priority != null
    ])
    error_message = "Priority routing needs a priority on every endpoint."
  }

  validation {
    condition = alltrue([
      for endpoint in var.external_endpoints :
      endpoint.priority == null || (
        endpoint.priority >= 1 &&
        endpoint.priority <= 1000 &&
        floor(endpoint.priority) == endpoint.priority
      )
    ])
    error_message = "An endpoint's priority must be a whole number from 1 to 1000."
  }

  validation {
    condition = alltrue([
      for endpoint in var.external_endpoints :
      endpoint.weight == null || (
        endpoint.weight >= 1 &&
        endpoint.weight <= 1000 &&
        floor(endpoint.weight) == endpoint.weight
      )
    ])
    error_message = "An endpoint's weight must be a whole number from 1 to 1000."
  }

  validation {
    condition = length(distinct([
      for endpoint in var.external_endpoints : endpoint.priority if endpoint.priority != null
      ])) == length([
      for endpoint in var.external_endpoints : endpoint.priority if endpoint.priority != null
    ])
    error_message = "Endpoint priorities must be distinct: Traffic Manager orders a profile's endpoints by priority, so two endpoints cannot share one. Each endpoint is a resource of its own, so nothing downstream can see the collision."
  }

  validation {
    condition = var.traffic_routing_method != "Performance" || alltrue([
      for endpoint in var.external_endpoints : endpoint.location != null
    ])
    error_message = "Performance routing needs a location on every endpoint - it is the region latency is measured to."
  }

  validation {
    condition = var.traffic_routing_method != "MultiValue" || alltrue([
      for endpoint in var.external_endpoints :
      can(cidrhost("${endpoint.target}/32", 0)) || can(cidrhost("${endpoint.target}/128", 0))
    ])
    error_message = "MultiValue routing needs an IPv4 or IPv6 address as every endpoint's target: it answers with several endpoints at once, which it can only do for address targets - the placeholder hostnames included. Use Priority, Weighted or Performance routing for hostname targets."
  }
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

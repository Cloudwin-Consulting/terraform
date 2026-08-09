variable "deployment_subscription_id" {
  description = "The Azure subscription into which resources will be deployed."
  type        = string
}

variable "deployment_location" {
  description = "The Azure location into which resources will be deployed."
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

variable "address_space" {
  description = "The address space of the example's own virtual network. It is standalone and unpeered, so the default sits outside the hub and spoke plan - change it before peering this network with anything."
  type        = string
  default     = "10.250.0.0/24"

  validation {
    condition     = can(cidrhost(var.address_space, 0))
    error_message = "address_space must be a valid CIDR prefix."
  }

  # cidrhost takes IPv6 as readily as IPv4, and every other rule here
  # is IPv4 arithmetic - the /2 to /29 bounds, the subnet's /27 floor,
  # and the capacity check's 32-bit address count. cidrnetmask is
  # IPv4-only, so it is the discriminator.
  validation {
    condition     = can(cidrnetmask(var.address_space))
    error_message = "address_space must be an IPv4 range: this example is single-stack, and Azure sizes IPv6 address spaces and subnets by their own rules (a /48 address space and /64 subnets), which the prefix bounds and gateway capacity checks here do not model."
  }

  # cidrhost quietly masks host bits away, so every other check here
  # would read 10.250.0.16/24 as 10.250.0.0/24 while Azure is handed
  # the original.
  validation {
    condition = try(
      var.address_space == "${cidrhost(var.address_space, 0)}/${split("/", var.address_space)[1]}",
      false
    )
    error_message = "address_space must start at its network address: 10.250.0.16/24 has host bits set, and the network it describes is 10.250.0.0/24."
  }

  validation {
    condition = try(
      tonumber(split("/", var.address_space)[1]) >= 2 && tonumber(split("/", var.address_space)[1]) <= 29,
      false
    )
    error_message = "address_space must be between a /2 and a /29: Azure accepts no virtual network address range outside those bounds."
  }
}

variable "application_gateway_subnet_name" {
  description = "The name of the dedicated gateway subnet. An Application Gateway v2 must be the only thing in its subnet."
  type        = string
  default     = "snet-application-gateway"
}

variable "application_gateway_subnet_prefix" {
  description = "The address prefix of the gateway subnet. /27 fits the default autoscale range; a gateway scaling past about 25 instances needs a /24."
  type        = string
  default     = "10.250.0.0/27"

  validation {
    condition     = can(cidrhost(var.application_gateway_subnet_prefix, 0))
    error_message = "application_gateway_subnet_prefix must be a valid CIDR prefix."
  }

  validation {
    condition     = can(cidrnetmask(var.application_gateway_subnet_prefix))
    error_message = "application_gateway_subnet_prefix must be an IPv4 range: this example is single-stack, and an IPv6 subnet in Azure is a /64 rather than anything the /27 floor and capacity checks here describe."
  }

  validation {
    condition     = tonumber(split("/", var.application_gateway_subnet_prefix)[1]) <= 27
    error_message = "The gateway subnet must be at least a /27: Azure reserves five addresses in it and the v2 SKU takes one per instance."
  }

  validation {
    condition = try(
      var.application_gateway_subnet_prefix == "${cidrhost(var.application_gateway_subnet_prefix, 0)}/${split("/", var.application_gateway_subnet_prefix)[1]}",
      false
    )
    error_message = "application_gateway_subnet_prefix must start at its network address: 10.250.0.16/27 has host bits set, and the subnet it describes is 10.250.0.0/27."
  }

  # Re-masking the subnet's network address with the network's own
  # prefix length lands on the network's network address only when the
  # subnet sits inside it - the containment check Terraform has no
  # function for.
  validation {
    condition = (
      tonumber(split("/", var.application_gateway_subnet_prefix)[1]) >= tonumber(split("/", var.address_space)[1]) &&
      cidrhost("${cidrhost(var.application_gateway_subnet_prefix, 0)}/${split("/", var.address_space)[1]}", 0) == cidrhost(var.address_space, 0)
    )
    error_message = "application_gateway_subnet_prefix must sit inside address_space: Azure rejects a subnet outside its virtual network's address space."
  }
}

variable "application_gateway_private_ip_address" {
  description = "The static private address of the gateway's internal frontend. Defaults to the tenth address of the gateway subnet, matching how the application spoke derives its own. An override must sit inside application_gateway_subnet_prefix and avoid the five addresses Azure reserves in every subnet - the first four and the last."
  type        = string
  default     = null

  validation {
    condition = var.application_gateway_private_ip_address == null || (
      can(cidrnetmask("${var.application_gateway_private_ip_address}/32")) &&
      try(
        cidrhost("${var.application_gateway_private_ip_address}/${split("/", var.application_gateway_subnet_prefix)[1]}", 0) == cidrhost(var.application_gateway_subnet_prefix, 0),
        false
      )
    )
    error_message = "application_gateway_private_ip_address must be an IPv4 address inside application_gateway_subnet_prefix: Azure only accepts a frontend address from the gateway's own subnet, and this example is single-stack."
  }

  validation {
    condition = var.application_gateway_private_ip_address == null || try(
      !contains([
        cidrhost(var.application_gateway_subnet_prefix, 0),
        cidrhost(var.application_gateway_subnet_prefix, 1),
        cidrhost(var.application_gateway_subnet_prefix, 2),
        cidrhost(var.application_gateway_subnet_prefix, 3),
        cidrhost(var.application_gateway_subnet_prefix, -1),
      ], var.application_gateway_private_ip_address),
      false
    )
    error_message = "application_gateway_private_ip_address may not be one of the five addresses Azure reserves in every subnet: the network address, the next three, and the broadcast address."
  }
}

variable "application_gateway_sku" {
  description = "The SKU and tier of the gateway: Standard_v2, or WAF_v2 to run the OWASP rule set in front of the backend."
  type        = string
  default     = "Standard_v2"

  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.application_gateway_sku)
    error_message = "application_gateway_sku must be Standard_v2 or WAF_v2."
  }
}

variable "application_gateway_waf_mode" {
  description = "The firewall mode when the WAF_v2 SKU is used: Prevention to block matching requests, or Detection to log them only. Ignored on Standard_v2."
  type        = string
  default     = "Prevention"

  validation {
    condition     = contains(["Detection", "Prevention"], var.application_gateway_waf_mode)
    error_message = "application_gateway_waf_mode must be Detection or Prevention."
  }
}

variable "application_gateway_min_capacity" {
  description = "The minimum autoscale capacity of the gateway. Zero is allowed, letting the gateway scale to nothing while idle."
  type        = number
  default     = 1

  validation {
    condition     = var.application_gateway_min_capacity >= 0 && var.application_gateway_min_capacity <= 100 && floor(var.application_gateway_min_capacity) == var.application_gateway_min_capacity
    error_message = "application_gateway_min_capacity must be a whole number between 0 and 100: capacity counts gateway instances."
  }
}

variable "application_gateway_max_capacity" {
  description = "The maximum autoscale capacity of the gateway. Every instance takes an address from the gateway subnet, so the subnet has to be large enough for the maximum: a /27 leaves 26 after Azure's five reserved addresses and the static private frontend, and a gateway scaling further needs a /26 or wider."
  type        = number
  default     = 2

  validation {
    condition     = var.application_gateway_max_capacity >= 2 && var.application_gateway_max_capacity <= 125 && floor(var.application_gateway_max_capacity) == var.application_gateway_max_capacity
    error_message = "application_gateway_max_capacity must be a whole number between 2 and 125: capacity counts gateway instances, and an autoscaling v2 gateway has no single-instance ceiling whatever its minimum."
  }

  validation {
    condition     = var.application_gateway_max_capacity >= var.application_gateway_min_capacity
    error_message = "application_gateway_max_capacity must be at least application_gateway_min_capacity."
  }

  # Azure reserves five addresses in every subnet and the internal
  # frontend takes a sixth, leaving the rest for gateway instances.
  validation {
    condition = try(
      var.application_gateway_max_capacity <= pow(2, 32 - tonumber(split("/", var.application_gateway_subnet_prefix)[1])) - 6,
      false
    )
    error_message = "application_gateway_max_capacity exceeds what the gateway subnet can address: each instance takes an address, and the subnet loses five to Azure's reservations plus one to the private frontend. Widen application_gateway_subnet_prefix or lower the maximum."
  }
}

variable "application_gateway_zones" {
  description = "Availability zones the gateway and its public IP are spread across, e.g. [\"1\", \"2\", \"3\"]. Leave null for a regional deployment."
  type        = list(string)
  default     = null

  validation {
    condition = var.application_gateway_zones == null || alltrue([
      for zone in coalesce(var.application_gateway_zones, []) :
      contains(["1", "2", "3"], zone)
    ])
    error_message = "application_gateway_zones may only contain \"1\", \"2\" and \"3\": an Azure region exposes three availability zones, and both the gateway and its public IP reject anything else."
  }

  validation {
    condition     = var.application_gateway_zones == null || length(distinct(coalesce(var.application_gateway_zones, []))) == length(coalesce(var.application_gateway_zones, []))
    error_message = "application_gateway_zones may not repeat a zone."
  }
}

variable "backend_fqdns" {
  description = "Hostnames of the backend pool members. The default is a dummy hostname, so the gateway deploys with the backend unhealthy - replace it with a real backend, e.g. a web app's default hostname. Mutually exclusive with backend_ip_addresses."
  type        = list(string)
  default     = ["placeholder-backend.example.com"]
}

variable "backend_ip_addresses" {
  description = "Addresses of the backend pool members, for a backend with no hostname of its own such as a Kubernetes internal load balancer frontend. Mutually exclusive with backend_fqdns."
  type        = list(string)
  default     = []
}

variable "backend_protocol" {
  description = "The protocol the gateway speaks to the backend: Https, or Http for a backend that terminates no TLS of its own."
  type        = string
  default     = "Https"

  validation {
    condition     = contains(["Http", "Https"], var.backend_protocol)
    error_message = "backend_protocol must be Http or Https."
  }
}

variable "backend_port" {
  description = "The port the gateway connects to on the backend."
  type        = number
  default     = 443

  validation {
    condition     = var.backend_port >= 1 && var.backend_port <= 65535 && floor(var.backend_port) == var.backend_port
    error_message = "backend_port must be a whole TCP port number from 1 to 65535."
  }
}

variable "backend_host_name" {
  description = "The host header the gateway sends to the backend. Leave null to take it from the backend address, which only an FQDN backend carries."
  type        = string
  default     = null
}

variable "backend_probe_path" {
  description = "The path probed to assess backend health."
  type        = string
  default     = "/"
}

variable "backend_probe_protocol" {
  description = "The protocol the health probe uses. Leave null to follow backend_protocol."
  type        = string
  default     = null
}

variable "ssl_certificate_key_vault_secret_id" {
  description = "The key vault secret ID of the listener's TLS certificate. Requires a user-assigned identity in identity_ids that can read it. Leave null for a plain HTTP listener - which is what this placeholder ships with."
  type        = string
  default     = null
}

variable "identity_ids" {
  description = "The user-assigned identity attached to the gateway, required to read a key vault TLS certificate. A list of at most one: an Application Gateway carries a single identity, and no system-assigned one at all."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.identity_ids) <= 1
    error_message = "identity_ids may name at most one identity: an Application Gateway supports a single user-assigned managed identity, so a second is rejected when the gateway is deployed."
  }
}

variable "enable_diagnostics" {
  description = "Whether to send the gateway's access, performance and firewall logs to the monitoring spoke's Log Analytics workspace. Requires the monitoring spoke to be deployed with enable_log_analytics."
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

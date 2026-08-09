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

variable "app_spoke_subscription_id" {
  description = "The Azure subscription the application spoke is deployed into, when it differs from this deployment's subscription. Leave null when they share a subscription. This stack's spoke lookups run against it, and the deployment identity needs read access to the referenced spoke resources there."
  type        = string
  default     = null
}

variable "app_spoke_deployment_name" {
  description = "The workload name of the application spoke this stack deploys into, without the environment (e.g. app-spoke). Its network resource group and virtual network are looked up as rg-<app_spoke_deployment_name>-<environment>-network and vnet-<app_spoke_deployment_name>-<environment>, and its core resource group - where the spoke keeps the services this stack publishes through - as rg-<app_spoke_deployment_name>-<environment>, so it must match the spoke stack's deployment_name and the spoke must be deployed into the same environment. A name that does not match fails this stack's lookups at plan time."
  type        = string
  default     = "app-spoke"
}

variable "aks_subnet_name" {
  description = "The name of the application spoke's AKS subnet, hosting the cluster's nodes and internal load balancer frontends. Must match a key of the spoke's subnets variable."
  type        = string
  default     = "snet-aks"
}

variable "private_endpoint_subnet_name" {
  description = "The name of the application spoke's private endpoint subnet. Must match a key of the spoke's subnets variable."
  type        = string
  default     = "snet-private-endpoints"
}

variable "hub_subscription_id" {
  description = "The Azure subscription the hub is deployed into, when it differs from this deployment's subscription. Leave null when they share a subscription. This stack's hub lookups run against it, and the deployment identity needs to read the hub's private DNS zones and to write this stack's private endpoint records into them (e.g. Private DNS Zone Contributor)."
  type        = string
  default     = null
}

variable "hub_deployment_name" {
  description = "The workload name of the hub this stack looks up, without the environment (e.g. hub-spoke). Its DNS resource group, where the hub keeps its private DNS zones, is looked up as rg-<hub_deployment_name>-<environment>-dns, so it must match the hub stack's deployment_name and the hub must be deployed into the same environment."
  type        = string
  default     = "hub-spoke"
}

variable "monitoring_subscription_id" {
  description = "The Azure subscription the monitoring spoke is deployed into, when it differs from this deployment's subscription. Leave null when they share a subscription. This stack's monitoring lookups run against it; diagnostics and agents reference the workspace by ID, which spans subscriptions."
  type        = string
  default     = null
}

variable "monitoring_deployment_name" {
  description = "The workload name of the monitoring spoke this stack sends diagnostics to, without the environment (e.g. monitoring-spoke). Its resource group and Log Analytics workspace are looked up as rg-<monitoring_deployment_name>-<environment> and log-<monitoring_deployment_name>-<environment>, so it must match the monitoring stack's deployment_name and the monitoring spoke must be deployed into the same environment."
  type        = string
  default     = "monitoring-spoke"
}

variable "kubernetes_version" {
  description = "The Kubernetes version of the control plane. Leave null for the platform's current default, kept on the latest patch release by the cluster's automatic upgrade channel."
  type        = string
  default     = null
}

variable "aks_sku_tier" {
  description = "The SKU tier of the cluster: Free or Standard. Standard adds the uptime SLA and is recommended for production."
  type        = string
  default     = "Free"
}

variable "private_cluster_enabled" {
  description = "Whether the cluster's API server is only reachable through its private endpoint. The example keeps the API server public - restricted to api_server_authorized_ip_ranges - so the deployment pipeline can apply the Kubernetes workload; enable this once deployments run from an agent inside the network."
  type        = bool
  default     = false
}

variable "api_server_authorized_ip_ranges" {
  description = "Address ranges allowed to reach the public API server, e.g. the deployment agents' and operators' egress addresses. Empty leaves the API server open to any address (authenticated with Microsoft Entra ID or the cluster's credentials); set the ranges wherever they are known. Not used on a private cluster."
  type        = list(string)
  default     = []
}

variable "entra_admin_group_object_ids" {
  description = "Object IDs of the Microsoft Entra ID groups granted cluster administrator access, enabling Entra ID integration with Azure RBAC for the data plane."
  type        = list(string)
  default     = []
}

variable "node_pool_vm_size" {
  description = "The size of the system node pool's virtual machines."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "node_pool_min_count" {
  description = "The minimum number of nodes the system node pool scales down to."
  type        = number
  default     = 1
}

variable "node_pool_max_count" {
  description = "The maximum number of nodes the system node pool scales out to. The spoke's /27 AKS subnet holds at most 27 node and load balancer frontend addresses."
  type        = number
  default     = 3
}

variable "availability_zones" {
  description = "Availability zones the node pool spreads across, e.g. [\"1\", \"2\", \"3\"]. Leave null for a regional deployment."
  type        = list(string)
  default     = null
}

variable "pod_cidr" {
  description = "The overlay address range pods draw their addresses from. Must equal the spoke's aks_pod_cidr exactly: the spoke builds the AKS subnet NSG's cluster-internal allowance from that value, so a differing range leaves cross-node pod traffic - including pod DNS queries to CoreDNS - blocked by the NSG's deny-all rule. Must not overlap the service CIDR or the network's routed ranges."
  type        = string
  default     = "10.244.0.0/16"

  # Checked here as well as in the aks module: this stack takes the
  # range apart to cross-check the deployed AKS subnet NSG, which
  # happens before the module's own validation is reached.
  validation {
    condition     = can(cidrhost(var.pod_cidr, 0)) && can(tonumber(split("/", var.pod_cidr)[1]))
    error_message = "pod_cidr must be a valid CIDR range, e.g. 10.244.0.0/16."
  }
}

variable "service_cidr" {
  description = "The address range Kubernetes services draw their cluster IPs from. Never leaves the cluster, but must not overlap the pod CIDR or the network's routed ranges."
  type        = string
  default     = "10.245.0.0/16"
}

variable "dns_service_ip" {
  description = "The cluster DNS service's address, from within service_cidr - but not its network address or first address, which the platform reserves."
  type        = string
  default     = "10.245.0.10"
}

variable "container_registry_name" {
  description = "The globally unique name of the container registry. Defaults to cr<deployment_name>-<environment> stripped of hyphens."
  type        = string
  default     = null
}

variable "container_registry_zone_redundancy_enabled" {
  description = "Whether the container registry is spread across availability zones."
  type        = bool
  default     = false
}

variable "container_registry_push_principal_ids" {
  description = "Principal IDs granted the AcrPush role to publish images from inside the network, e.g. a build agents group object ID."
  type        = list(string)
  default     = []
}

variable "rabbitmq_image" {
  description = "The RabbitMQ image backing the order queue. The default public image lets the first deployment succeed before any image has been pushed to the registry."
  type        = string
  default     = "rabbitmq:4.3.2-management-alpine"
}

variable "order_service_image" {
  description = "The order service's container image. The default public sample image lets the first deployment succeed before any image has been pushed to the registry."
  type        = string
  default     = "ghcr.io/azure-samples/aks-store-demo/order-service:2.2.0"
}

variable "product_service_image" {
  description = "The product service's container image. The default public sample image lets the first deployment succeed before any image has been pushed to the registry."
  type        = string
  default     = "ghcr.io/azure-samples/aks-store-demo/product-service:2.2.0"
}

variable "store_front_image" {
  description = "The store front's container image. The default public sample image lets the first deployment succeed before any image has been pushed to the registry."
  type        = string
  default     = "ghcr.io/azure-samples/aks-store-demo/store-front:2.2.0"
}

variable "wait_for_queue_image" {
  description = "The image of the init container that holds the order service back until the queue accepts connections."
  type        = string
  default     = "busybox:1.37.0"
}

variable "order_service_replicas" {
  description = "The number of replicas of the order service."
  type        = number
  default     = 1
}

variable "product_service_replicas" {
  description = "The number of replicas of the product service."
  type        = number
  default     = 1
}

variable "store_front_replicas" {
  description = "The number of replicas of the store front."
  type        = number
  default     = 1
}

variable "store_front_load_balancer_ip" {
  description = "The address the store front's internal load balancer frontend takes in the AKS subnet - the application spoke's aks_ingress_ip_address, which must match this value exactly. Required by both entry points: the spoke's application gateway deploys before this stack and needs a fixed address for its backend pool, and the private link service selects the frontend it publishes by address. Leave null to let the cluster take any free address, in which case neither entry point can be enabled."
  type        = string
  default     = null

  validation {
    condition     = var.store_front_load_balancer_ip == null || can(cidrhost("${var.store_front_load_balancer_ip}/32", 0))
    error_message = "store_front_load_balancer_ip must be a valid IP address, e.g. 10.240.6.190."
  }
}

# ------------------------------------------------------------
# Entry points publishing the store front beyond the network
# ------------------------------------------------------------

variable "enable_application_gateway_backend" {
  description = "Whether to check at plan time that the spoke's application gateway publishes this cluster's store front. Creates nothing: the gateway's backend pool is an inline block of the spoke's gateway, so only the spoke can write it. Enable it alongside the spoke's application_gateway_backend_ip_addresses so a drifted address fails the plan instead of serving 502s."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_application_gateway_backend || var.store_front_load_balancer_ip != null
    error_message = "enable_application_gateway_backend requires store_front_load_balancer_ip: the gateway's backend pool names a fixed address, so the store front's load balancer must take one."
  }
}

variable "application_gateway_name" {
  description = "The name of the spoke's application gateway, checked by enable_application_gateway_backend. Defaults to the name the spoke derives, agw-<app_spoke_deployment_name>-<environment>; set it only to check a gateway named some other way."
  type        = string
  default     = null
}

variable "enable_private_link_service" {
  description = "Whether to publish the store front's internal load balancer through a private link service, so consumers outside the network - Front Door Premium below - reach it with a private endpoint. Requires the spoke's private link service subnet."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_private_link_service || var.store_front_load_balancer_ip != null
    error_message = "enable_private_link_service requires store_front_load_balancer_ip: the service selects the load balancer frontend it publishes by address, because the cluster names that frontend after the Kubernetes service's identifier."
  }
}

variable "private_link_service_subnet_name" {
  description = "The name of the spoke subnet the private link service draws its NAT addresses from. Must have its private link service network policies disabled."
  type        = string
  default     = "snet-private-link-service"
}

variable "private_link_service_nat_ip_count" {
  description = "How many NAT addresses the private link service takes from the subnet. Each one adds capacity for simultaneous connections; one is enough for a single Front Door origin."
  type        = number
  default     = 1
}

variable "enable_front_door_endpoint" {
  description = "Whether to add a Front Door endpoint for the store front to the application spoke's profile, reaching it over the private link service. Requires the spoke's enable_front_door with the Premium SKU, and this stack's enable_private_link_service."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_front_door_endpoint || var.enable_private_link_service
    error_message = "enable_front_door_endpoint requires enable_private_link_service: the store front has no public endpoint for Front Door to reach, so the origin is only reachable over Private Link."
  }
}

variable "front_door_profile_name" {
  description = "The name of the application spoke's Front Door profile the endpoint is added to. Defaults to the name the spoke derives, afd-<app_spoke_deployment_name>-<environment> (e.g. afd-app-spoke-dev); set it only when the spoke's front_door_name was overridden. Must be a Premium profile: private link origins are not supported on the Standard SKU."
  type        = string
  default     = null
}

variable "front_door_endpoint_name" {
  description = "The name of the Front Door endpoint. Must be globally unique as it forms the default hostname. Defaults to fde-<deployment_name>-<environment>."
  type        = string
  default     = null
}

variable "front_door_health_probe_path" {
  description = "The path Front Door probes to assess the store front's health."
  type        = string
  default     = "/health"
}

variable "pim_operations_principals" {
  description = "Object IDs of the principals made eligible for the operations role on the workload's resource group through Privileged Identity Management, keyed by a short label, e.g. { operations = \"<group object ID>\" }. Prefer groups, so membership changes need no deployment. Empty deploys no PIM configuration. Requires Microsoft Entra ID P2 licensing."
  type        = map(string)
  default     = {}
}

variable "pim_operations_role_definition_name" {
  description = "The role the eligible principals activate on the workload's resource group."
  type        = string
  default     = "Contributor"
}

variable "pim_operations_maximum_activation_duration" {
  description = "The longest a single activation of the operations role lasts, as an ISO 8601 duration."
  type        = string
  default     = "PT8H"
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
  default     = "ApplicationPlatform"

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

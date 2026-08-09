deployment_subscription_id = "<subscription_id>"
deployment_location        = "uksouth"
deployment_name            = "aks"
environment                = "prod"

# ------------------------------------------------------------
# The standard tags every resource in this stack carries.
# ------------------------------------------------------------
application         = "aks"
environment_tag     = "Production"
owner               = "CloudEngineering"
cost_center         = "aks"
criticality         = "High"
service             = "ApplicationPlatform"
data_classification = "Confidential"
lifecycle_stage     = "Permanent"
repository          = "terraform-template"

# Optional tags, left off entirely rather than applied empty.
expiry_date   = null
business_unit = null

app_spoke_subscription_id = null
app_spoke_deployment_name = "app-spoke"

hub_subscription_id = null
hub_deployment_name = "hub-spoke"

monitoring_subscription_id = null
monitoring_deployment_name = "monitoring-spoke"

# The example keeps the API server public - authenticated with the
# cluster's credentials and restricted to any ranges below - so the
# pipeline can apply the Kubernetes workload in the same run. Set
# private_cluster_enabled = true once deployments run from an agent
# inside the network.
private_cluster_enabled         = false
api_server_authorized_ip_ranges = []

# Production runs the Standard tier for the uptime SLA, spreads the
# nodes (and the registry) across availability zones, sizes the pool
# up and scales the workload out.
aks_sku_tier = "Standard"

availability_zones = ["1", "2", "3"]

node_pool_vm_size   = "Standard_D4s_v3"
node_pool_min_count = 2
node_pool_max_count = 5

container_registry_zone_redundancy_enabled = true

order_service_replicas   = 2
product_service_replicas = 2
store_front_replicas     = 2

# ------------------------------------------------------------
# Remaining inputs, pinned to their defaults so this file shows the
# full configuration being applied in this environment.
# ------------------------------------------------------------
aks_subnet_name              = "snet-aks"
private_endpoint_subnet_name = "snet-private-endpoints"
kubernetes_version           = null
# The overlay and service ranges. pod_cidr must equal the application
# spoke's aks_pod_cidr - the spoke builds the AKS subnet NSG's
# cluster-internal allowance from it.
pod_cidr                              = "10.244.0.0/16"
service_cidr                          = "10.245.0.0/16"
dns_service_ip                        = "10.245.0.10"
entra_admin_group_object_ids          = []
container_registry_name               = null
container_registry_push_principal_ids = []
rabbitmq_image                        = "rabbitmq:4.3.2-management-alpine"
order_service_image                   = "ghcr.io/azure-samples/aks-store-demo/order-service:2.2.0"
product_service_image                 = "ghcr.io/azure-samples/aks-store-demo/product-service:2.2.0"
store_front_image                     = "ghcr.io/azure-samples/aks-store-demo/store-front:2.2.0"
wait_for_queue_image                  = "busybox:1.37.0"
# Entry points publishing the store front beyond the network, all off.
# Turning either on starts with store_front_load_balancer_ip, which must
# equal the application spoke's aks_ingress_ip_address (10.240.6.190
# with the default addressing): the spoke's gateway deploys before this
# stack and needs a fixed address, and the private link service selects
# the load balancer frontend it publishes by address.
store_front_load_balancer_ip       = null
enable_application_gateway_backend = false
application_gateway_name           = null
enable_private_link_service        = false
private_link_service_subnet_name   = "snet-private-link-service"
private_link_service_nat_ip_count  = 1
enable_front_door_endpoint         = false
front_door_profile_name            = null
front_door_endpoint_name           = null
front_door_health_probe_path       = "/health"

pim_operations_principals                  = {}
pim_operations_role_definition_name        = "Contributor"
pim_operations_maximum_activation_duration = "PT8H"

tags = {}

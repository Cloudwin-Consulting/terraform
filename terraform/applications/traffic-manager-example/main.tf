locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  resource_group_name  = "rg-${local.name_suffix}"
  traffic_manager_name = "traf-${local.name_suffix}"
  dns_relative_name    = coalesce(var.traffic_manager_dns_name, local.name_suffix)

  # The Environment tag holds the standard name of the environment,
  # while var.environment keeps the short form every resource name is
  # derived from - so the tag standard renames nothing.
  standard_environment_tags = {
    rd   = "RD"
    dev  = "Development"
    qa   = "QA"
    prod = "Production"
  }

  # The optional tags only join the set once they have a value, so no
  # resource carries an empty ExpiryDate, BusinessUnit or Repository.
  optional_tags = merge(
    var.expiry_date != null ? { ExpiryDate = var.expiry_date } : {},
    var.business_unit != null ? { BusinessUnit = var.business_unit } : {},
    var.repository != null ? { Repository = var.repository } : {},
  )

  # The tag set every resource in this stack carries: set on the
  # resources declared here and passed to every shared module, so
  # each resource is tagged in its own right rather than relying on
  # resource group tag inheritance. var.tags is merged last, so a
  # deployment can add to - or override - the standard values.
  common_tags = merge(
    {
      Application        = coalesce(var.application, var.deployment_name)
      Environment        = coalesce(var.environment_tag, lookup(local.standard_environment_tags, lower(var.environment), null))
      Owner              = var.owner
      CostCenter         = coalesce(var.cost_center, var.application, var.deployment_name)
      ManagedBy          = "Terraform"
      Criticality        = var.criticality
      Service            = var.service
      DataClassification = var.data_classification
      Lifecycle          = var.lifecycle_stage
    },
    local.optional_tags,
    var.tags,
  )
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.deployment_location
  tags     = local.common_tags
}

# ------------------------------------------------------------
# Traffic Manager - placeholder example
#
# A DNS-based global entry point: the profile answers queries for
# <dns_relative_name>.trafficmanager.net with one of its endpoints,
# picked by the routing method. Nothing proxies traffic - a client
# resolves the name and then connects to the endpoint directly - so
# the endpoints must be reachable by the client themselves.
#
# The endpoints are deliberately dummy hostnames
# (placeholder-*.example.com) and are served without probing, which is
# what makes the example deployable on its own: Traffic Manager probes
# from the public internet, so an endpoint it cannot reach - a dummy
# hostname here, a private workload in a real deployment - is marked
# degraded and taken out of rotation unless always_serve_enabled
# bypasses the probe.
#
# To adopt it, replace each target with a real hostname: an App Service
# default hostname, an application gateway's public address, a Front
# Door endpoint. With probing left on (always_serve_enabled = false)
# the profile then fails traffic away from an endpoint whose
# monitor_path stops answering, which is the point of running it at
# all.
# ------------------------------------------------------------

module "traffic_manager" {
  source = "../../shared/traffic-manager"

  name                   = local.traffic_manager_name
  resource_group_name    = azurerm_resource_group.this.name
  dns_relative_name      = local.dns_relative_name
  dns_ttl                = var.dns_ttl
  traffic_routing_method = var.traffic_routing_method
  tags                   = local.common_tags

  monitor_protocol = var.monitor_protocol
  monitor_port     = var.monitor_port
  monitor_path     = var.monitor_path

  external_endpoints = var.external_endpoints
}

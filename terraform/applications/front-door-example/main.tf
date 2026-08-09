locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  # The upstream stacks this one looks up derive their names the
  # same way, from their own workload name and this environment.
  log_analytics_workspace_name   = "log-${var.monitoring_deployment_name}-${var.environment}"
  monitoring_resource_group_name = "rg-${var.monitoring_deployment_name}-${var.environment}"

  resource_group_name = "rg-${local.name_suffix}"
  front_door_name     = coalesce(var.front_door_name, "afd-${local.name_suffix}")

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
# Existing platform resources: the monitoring workspace the profile's
# access and WAF logs are sent to.
# ------------------------------------------------------------

data "azurerm_log_analytics_workspace" "monitoring" {
  provider = azurerm.monitoring

  count = var.enable_diagnostics ? 1 : 0

  name                = local.log_analytics_workspace_name
  resource_group_name = local.monitoring_resource_group_name
}

# ------------------------------------------------------------
# Front Door - placeholder example
#
# A Front Door profile with one endpoint, origin group, origin and
# route per entry in front_door_endpoints. The origins are deliberately
# dummy hostnames (placeholder-*.example.com): the stack deploys a
# complete, correctly shaped global entry point that resolves and
# serves TLS on its own <endpoint>.z01.azurefd.net hostname, and every
# origin reports unhealthy until the hostnames are pointed at something
# real - Front Door answers 503 in the meantime, which is the expected
# state of this example rather than a deployment failure.
#
# To adopt it, replace each origin_host_name with a real origin. For a
# private origin - an App Service or a private link service that keeps
# public network access disabled - set the entry's private_link as well
# (see the app1, app2 and aks stacks, which do exactly that), which
# needs the Premium SKU and the pending private endpoint connection on
# the origin approved after the first deployment.
# ------------------------------------------------------------

module "front_door" {
  source = "../../shared/front-door"

  name                     = local.front_door_name
  resource_group_name      = azurerm_resource_group.this.name
  sku_name                 = var.front_door_sku
  response_timeout_seconds = var.front_door_response_timeout_seconds
  tags                     = local.common_tags

  log_analytics_workspace_id = var.enable_diagnostics ? data.azurerm_log_analytics_workspace.monitoring[0].id : null
}

module "front_door_endpoint" {
  source = "../../shared/front-door-endpoint"

  for_each = var.front_door_endpoints

  name                  = coalesce(each.value.endpoint_name, "fde-${local.name_suffix}-${each.key}")
  front_door_profile_id = module.front_door.id
  tags                  = local.common_tags

  origin_host_name           = each.value.origin_host_name
  origin_http_port           = each.value.origin_http_port
  origin_https_port          = each.value.origin_https_port
  origin_forwarding_protocol = each.value.origin_forwarding_protocol

  health_probe_path     = each.value.health_probe_path
  health_probe_protocol = each.value.health_probe_protocol

  # A placeholder origin has no certificate matching its hostname, so
  # the check is off by default here. Turn it back on - as the module
  # defaults to - for a real origin serving a certificate for the
  # hostname it is named by.
  certificate_name_check_enabled = each.value.certificate_name_check_enabled

  private_link = each.value.private_link
}

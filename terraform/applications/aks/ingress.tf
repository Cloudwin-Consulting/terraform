# ------------------------------------------------------------
# Publishing the store front beyond the virtual network
#
# The store front's own entry point is the internal load balancer
# frontend workload.tf creates: a private address in the spoke's AKS
# subnet, reachable from the hub and spoke network and nowhere else.
# Two optional paths carry traffic to it from outside, and neither is
# on by default.
#
# Through the spoke's application gateway (enable_application_gateway_
# backend). The gateway's private listener is what the hub firewall's
# inbound DNAT rule publishes, so the path runs internet -> firewall
# public IP -> gateway private frontend -> this cluster. The gateway's
# backend pool is an inline block of the spoke's gateway resource, so
# the spoke writes it and this stack only checks it: the two stacks
# agree on store_front_load_balancer_ip / aks_ingress_ip_address, and
# the check below fails the plan when they have drifted.
#
# Through Front Door (enable_private_link_service and enable_front_door_
# endpoint). A private link service publishes the internal load balancer
# frontend, and a Front Door Premium origin reaches it over Private
# Link, so the cluster gains a global entry point without any public
# address of its own. Front Door's connection to the service arrives
# pending and must be approved by hand after the first deployment.
# ------------------------------------------------------------

# ------------------------------------------------------------
# Application gateway backend cross-check
#
# Creates nothing. The spoke deploys before this stack and cannot
# discover the frontend address the cluster has not taken yet, so it is
# given the address instead - and a wrong address costs nothing at
# apply time and everything at request time, where it reads as the
# gateway serving 502s from a backend it reports unhealthy. Read the
# gateway back and refuse to plan while no backend pool names this
# stack's store_front_load_balancer_ip.
# ------------------------------------------------------------

data "azurerm_application_gateway" "spoke" {
  provider = azurerm.app_spoke

  count = var.enable_application_gateway_backend ? 1 : 0

  name                = local.application_gateway_name
  resource_group_name = local.app_spoke_resource_group_name

  lifecycle {
    postcondition {
      # A routing rule has to pair a pool that names this cluster's
      # frontend with settings that reach it the way the store front
      # actually serves. Naming the address is not enough on its own:
      # the gateway's backend protocol and port default to Https and
      # 443, and a spoke that sets the address while leaving those
      # alone deploys a gateway that reports the backend unhealthy and
      # answers 502 - which is the failure this check exists to catch,
      # not one it should pass over.
      #
      # 80 and Http are literals because kubernetes_service.store_front
      # publishes port 80 and the container serves plain HTTP; change
      # the service's port and this moves with it. Reading them off the
      # service resource instead would make this gateway lookup depend
      # on the service and defer the whole check to apply time, losing
      # the plan-time failure that is the point of it.
      condition = anytrue([
        for rule in self.request_routing_rule :
        anytrue([
          for pool in self.backend_address_pool :
          pool.name == rule.backend_address_pool_name &&
          contains(pool.ip_addresses, var.store_front_load_balancer_ip)
          ]) && anytrue([
          for settings in self.backend_http_settings :
          settings.name == rule.backend_http_settings_name &&
          lower(settings.protocol) == "http" &&
          settings.port == 80
        ])
      ])
      error_message = "No routing rule in ${self.name} serves ${var.store_front_load_balancer_ip} over HTTP on port 80, so the gateway would answer this cluster's listener from a backend it reports unhealthy. In the spoke, put that address in application_gateway_backend_ip_addresses, set application_gateway_backend_protocol = \"Http\" and application_gateway_backend_port = 80, and apply the spoke first."
    }
  }
}

# ------------------------------------------------------------
# Private link service over the cluster's internal load balancer
# ------------------------------------------------------------

data "azurerm_subnet" "private_link_service" {
  provider = azurerm.app_spoke

  count = var.enable_private_link_service ? 1 : 0

  name                 = var.private_link_service_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
}

# The load balancer the cluster stands up for the store front's
# LoadBalancer service, in the platform-managed node resource group.
# The cluster names it "kubernetes-internal" but names its frontend
# configurations after the Kubernetes service's identifier, so the
# frontend is selected by address below rather than by name - which is
# what store_front_load_balancer_ip makes possible.
#
# It does not exist until the service has applied, so this reads at
# apply time on a first deployment. Nothing may take a count or a
# for_each from it; the enable_* variables decide what is created.
data "azurerm_lb" "kubernetes_internal" {
  count = var.enable_private_link_service ? 1 : 0

  name                = "kubernetes-internal"
  resource_group_name = module.aks.node_resource_group_name

  depends_on = [kubernetes_service.store_front]

  lifecycle {
    postcondition {
      condition = length([
        for configuration in self.frontend_ip_configuration : configuration.id
        if configuration.private_ip_address == var.store_front_load_balancer_ip
      ]) == 1
      error_message = "No frontend of ${self.name} holds ${var.store_front_load_balancer_ip}, so there is nothing for the private link service to publish. The store front's load balancer takes that address from store_front_load_balancer_ip - check the service applied with it."
    }
  }
}

# The service translates each consumer connection through a NAT address
# in the spoke's private link service subnet. Front Door requests its
# connection from a Microsoft-owned subscription that cannot be named
# in advance, so the service is visible to any subscription - but with
# no subscription auto-approved, visible only means allowed to ask:
# every connection still waits for an approval.
module "store_front_private_link_service" {
  source = "../../shared/private-link-service"

  count = var.enable_private_link_service ? 1 : 0

  name                = "pls-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  nat_subnet_id       = data.azurerm_subnet.private_link_service[0].id
  nat_ip_count        = var.private_link_service_nat_ip_count
  tags                = local.common_tags

  load_balancer_frontend_ip_configuration_ids = [
    one([
      for configuration in data.azurerm_lb.kubernetes_internal[0].frontend_ip_configuration :
      configuration.id
      if configuration.private_ip_address == var.store_front_load_balancer_ip
    ])
  ]

  visibility_subscription_ids    = ["*"]
  auto_approval_subscription_ids = []
}

# ------------------------------------------------------------
# Front Door endpoint (optional) on the spoke's shared profile
#
# The origin is the store front's load balancer frontend, reached over
# the private link service above, so the cluster keeps no public
# address. Approve the pending connection on the private link service
# after the first deployment - until then the origin reports unhealthy
# and the endpoint serves 503.
#
# The origin leg is plain HTTP: the store front terminates no TLS of
# its own, and an origin named by address could not have its
# certificate validated even if it did. Clients still reach Front Door
# over HTTPS, and the origin leg stays on the Microsoft backbone and
# inside Private Link - but it is unencrypted, so anything with a
# foothold on that path sees plaintext. Terminating TLS inside the
# cluster and switching origin_forwarding_protocol to HttpsOnly is the
# stronger posture wherever the workload can carry a certificate.
# ------------------------------------------------------------

data "azurerm_cdn_frontdoor_profile" "spoke" {
  provider = azurerm.app_spoke

  count = var.enable_front_door_endpoint ? 1 : 0

  name                = local.front_door_profile_name
  resource_group_name = local.app_spoke_resource_group_name

  lifecycle {
    # The endpoint reaches the private store front through a Private
    # Link origin, which only Front Door Premium supports.
    postcondition {
      condition     = self.sku_name == "Premium_AzureFrontDoor"
      error_message = "The spoke's Front Door profile must be Premium_AzureFrontDoor: private link origins are not supported on the Standard SKU."
    }
  }
}

module "front_door_endpoint" {
  source = "../../shared/front-door-endpoint"

  count = var.enable_front_door_endpoint ? 1 : 0

  # The endpoint and its origin group, origin and route live on the
  # spoke's Front Door profile, so they are created in the spoke's
  # subscription.
  providers = {
    azurerm = azurerm.app_spoke
  }

  name                  = coalesce(var.front_door_endpoint_name, "fde-${local.name_suffix}")
  front_door_profile_id = data.azurerm_cdn_frontdoor_profile.spoke[0].id
  origin_host_name      = var.store_front_load_balancer_ip
  health_probe_path     = var.front_door_health_probe_path
  tags                  = local.common_tags

  origin_http_port               = 80
  origin_forwarding_protocol     = "HttpOnly"
  health_probe_protocol          = "Http"
  certificate_name_check_enabled = false

  private_link = {
    target_id = module.store_front_private_link_service[0].id
    # A private link service publishes a load balancer rather than a
    # subresource of a PaaS origin, so it names no target type.
    target_type = null
    location    = azurerm_resource_group.this.location
  }
}

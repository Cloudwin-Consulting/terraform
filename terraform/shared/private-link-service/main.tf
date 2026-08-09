terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A private link service, publishing a standard internal load balancer
# frontend to consumers that connect with a private endpoint - e.g. a
# Front Door Premium private link origin, or a consumer in another
# subscription that holds the service's alias.
#
# The service translates each incoming connection through a NAT address
# in nat_subnet_id, so that subnet must have its private link service
# network policies disabled (the vnet module's
# private_link_service_network_policies_enabled). Azure does not apply
# network security group rules to these NAT interfaces.
#
# Connections arrive pending and stay that way until they are approved,
# unless the consumer's subscription is listed in
# auto_approval_subscription_ids. Front Door's connection is approved
# by hand after the first deployment.

resource "azurerm_private_link_service" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  load_balancer_frontend_ip_configuration_ids = var.load_balancer_frontend_ip_configuration_ids

  proxy_protocol_enabled = var.proxy_protocol_enabled

  # Which subscriptions may see the service by its alias, and which of
  # those connect without an approval step. Empty visibility keeps the
  # service reachable only by the subscriptions that own it and by
  # Microsoft services granted access out of band, e.g. Front Door.
  visibility_subscription_ids    = var.visibility_subscription_ids
  auto_approval_subscription_ids = var.auto_approval_subscription_ids

  # One NAT address per configuration, drawn dynamically from the NAT
  # subnet. The first is the primary. More configurations raise the
  # number of simultaneous connections the service can translate.
  dynamic "nat_ip_configuration" {
    for_each = range(var.nat_ip_count)

    content {
      name      = "nat-${nat_ip_configuration.value}"
      subnet_id = var.nat_subnet_id
      primary   = nat_ip_configuration.value == 0
    }
  }
}

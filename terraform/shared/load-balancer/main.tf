terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A Standard load balancer with a single backend pool, fronted either
# by a private address on a subnet or by a public IP. Associate virtual
# machine network interfaces with the backend pool from the calling
# stack.

# Azure allows one kind of frontend per load balancer: every frontend
# configuration references a subnet or every one references a public IP,
# never a mixture (LoadBalancerReferencesBothPublicIPAndSubnet). So
# public_ip_enabled switches the frontend rather than adding to it, and
# the module carries a single frontend either way.
locals {
  frontend_name = var.public_ip_enabled ? "public" : "internal"
}

# The static public IP an internet-facing frontend answers on. Off by
# default: a load balancer only becomes reachable from the internet
# when a stack asks for it.
resource "azurerm_public_ip" "this" {
  count = var.public_ip_enabled ? 1 : 0

  name                = "${var.name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  tags                = var.tags
}

# A frontend's type is fixed once Azure has created it: a deployed load
# balancer cannot be converted between private and public, so flipping
# the flag has to build a new one rather than update the deployed one,
# which the API rejects. Replacing this single resource is what gets
# that ordered correctly - Terraform destroys before it creates, and
# the replacement carries the same name, so the two cannot overlap in
# Azure. The pool, probes and rules follow the new load balancer, and
# the calling stack re-associates its network interfaces with the new
# pool.
#
# The trigger compares against a value already in state, so it cannot
# fire on the apply that first introduces it: a deployment adopting
# this module version and switching its frontend in one apply has to
# ask for the replacement itself, with
# -replace=module.<name>.azurerm_lb.this. Every later switch is
# planned on its own.
resource "terraform_data" "frontend_type" {
  triggers_replace = [local.frontend_name]
}

resource "azurerm_lb" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                          = local.frontend_name
    subnet_id                     = var.public_ip_enabled ? null : var.subnet_id
    private_ip_address_allocation = var.public_ip_enabled ? null : "Dynamic"
    public_ip_address_id          = one(azurerm_public_ip.this[*].id)
    zones                         = var.zones
  }

  lifecycle {
    replace_triggered_by = [terraform_data.frontend_type]
  }
}

# The single backend pool network interfaces are associated with.
resource "azurerm_lb_backend_address_pool" "this" {
  name            = "${var.name}-backend"
  loadbalancer_id = azurerm_lb.this.id
}

# One health probe per rule.
resource "azurerm_lb_probe" "this" {
  for_each = { for rule in var.rules : rule.name => rule }

  name                = "${each.value.name}-probe"
  loadbalancer_id     = azurerm_lb.this.id
  protocol            = each.value.probe_protocol
  port                = coalesce(each.value.probe_port, each.value.backend_port)
  request_path        = each.value.probe_request_path
  interval_in_seconds = 15
  number_of_probes    = 2
}

# The load balancing rules, each bound to its probe.
resource "azurerm_lb_rule" "this" {
  for_each = { for rule in var.rules : rule.name => rule }

  name                           = each.value.name
  loadbalancer_id                = azurerm_lb.this.id
  frontend_ip_configuration_name = local.frontend_name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.this.id]
  probe_id                       = azurerm_lb_probe.this[each.key].id
  protocol                       = each.value.protocol
  frontend_port                  = each.value.frontend_port
  backend_port                   = each.value.backend_port
  idle_timeout_in_minutes        = 4

  # Outbound SNAT stays off the rules: backend machines get their
  # explicit outbound path from a NAT gateway on their subnet (or a
  # route through the hub firewall), never implicitly from this load
  # balancer - including when it has a public frontend, which carries
  # inbound traffic only.
  disable_outbound_snat = true
}

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A NAT gateway giving the associated subnets an explicit, scalable
# outbound path. Standard internal load balancers provide no outbound
# connectivity and Azure's default outbound access is being retired, so
# subnets hosting machines that reach the internet (OS updates,
# package mirrors) associate with this - unless a route table sends
# their egress through the hub firewall instead.

# The static public IP outbound flows translate to.
resource "azurerm_public_ip" "this" {
  name                = "${var.name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zone == null ? null : [var.zone]
  tags                = var.tags
}

# The NAT gateway itself. NAT gateways are zonal: they sit in one zone
# (or no zone) and serve the whole subnet regardless of the zone its
# machines run in.
resource "azurerm_nat_gateway" "this" {
  name                    = var.name
  resource_group_name     = var.resource_group_name
  location                = var.location
  sku_name                = "Standard"
  idle_timeout_in_minutes = var.idle_timeout_in_minutes
  zones                   = var.zone == null ? null : [var.zone]
  tags                    = var.tags
}

# Attaches the public IP to the gateway.
resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.this.id
}

# Associates the gateway with each subnet, taking over its outbound
# path.
resource "azurerm_subnet_nat_gateway_association" "this" {
  for_each = var.subnet_ids

  subnet_id      = each.value
  nat_gateway_id = azurerm_nat_gateway.this.id
}

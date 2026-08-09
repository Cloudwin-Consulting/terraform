terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The virtual network.
resource "azurerm_virtual_network" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space
  dns_servers         = var.dns_servers
  tags                = var.tags
}

# Subnets in the virtual network, with optional service endpoints and
# delegations.
resource "azurerm_subnet" "this" {
  #checkov:skip=CKV2_AZURE_31: NSG associations are made by the shared nsg module (azurerm_subnet_network_security_group_association), which Checkov cannot link to these subnets across module boundaries. Azure also forbids NSGs on some reserved subnets, e.g. AzureFirewallSubnet and GatewaySubnet.
  for_each = var.subnets

  name                 = each.key
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = each.value.address_prefixes
  service_endpoints    = each.value.service_endpoints

  # "Enabled" allows network security groups to filter traffic destined
  # for private endpoints deployed into the subnet.
  private_endpoint_network_policies = each.value.private_endpoint_network_policies

  # A private link service's NAT addresses cannot be created in a subnet
  # that still enforces network policies on them, so a subnet hosting one
  # sets this to false.
  private_link_service_network_policies_enabled = each.value.private_link_service_network_policies_enabled

  dynamic "delegation" {
    for_each = each.value.delegation == null ? [] : [each.value.delegation]

    content {
      name = delegation.value.name

      service_delegation {
        name    = delegation.value.service_name
        actions = delegation.value.actions
      }
    }
  }
}

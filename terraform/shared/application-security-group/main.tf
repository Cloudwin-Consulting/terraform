terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# An application security group. Network interfaces join it through the
# virtual machine modules' application_security_group_ids input, and
# network security group rules reference it as a source or destination
# instead of address prefixes - so rules describe workloads, not IP
# ranges, and scale-out needs no rule changes.
resource "azurerm_application_security_group" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

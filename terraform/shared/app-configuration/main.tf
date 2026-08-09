terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The App Configuration store. Access is with Microsoft Entra ID and
# RBAC through a private endpoint.
resource "azurerm_app_configuration" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  tags                = var.tags

  # Secure defaults: no access keys (use Microsoft Entra ID and RBAC),
  # no public network access, and soft delete with purge protection.
  # Data plane access is via a private endpoint.
  local_auth_enabled         = false
  public_network_access      = var.public_network_access
  purge_protection_enabled   = var.purge_protection_enabled
  soft_delete_retention_days = var.soft_delete_retention_days

  identity {
    type = "SystemAssigned"
  }
}

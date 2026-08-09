terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The registry. Access is with managed identities and RBAC through a
# private endpoint.
resource "azurerm_container_registry" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  tags                = var.tags

  # Secure defaults: no admin account, no anonymous pulls and no public
  # network access (which requires the Premium SKU). Images are pulled
  # through a private endpoint with managed identities and RBAC.
  admin_enabled                 = false
  anonymous_pull_enabled        = false
  public_network_access_enabled = var.public_network_access_enabled
  network_rule_bypass_option    = "AzureServices"
  zone_redundancy_enabled       = var.zone_redundancy_enabled

  identity {
    type = "SystemAssigned"
  }
}

# Workloads pull with AcrPull assigned by their stack. Publishing
# images happens from inside the network (e.g. the hub jump box or a
# self-hosted agent) by the principals granted AcrPush here.
resource "azurerm_role_assignment" "pushers" {
  for_each = toset(var.push_principal_ids)

  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPush"
  principal_id         = each.value
}

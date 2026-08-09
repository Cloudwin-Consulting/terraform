terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The namespace. Access is with Microsoft Entra ID and RBAC through a
# private endpoint.
resource "azurerm_servicebus_namespace" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  capacity            = var.sku == "Premium" ? var.capacity : 0
  tags                = var.tags

  # Secure defaults: TLS 1.2, no shared access keys (use Microsoft
  # Entra ID and RBAC) and no public network access. The Premium SKU is
  # the default because it is required for private endpoints.
  minimum_tls_version           = "1.2"
  local_auth_enabled            = false
  public_network_access_enabled = var.public_network_access_enabled

  identity {
    type = "SystemAssigned"
  }
}

# Queues in the namespace.
resource "azurerm_servicebus_queue" "this" {
  for_each = toset(var.queues)

  name         = each.value
  namespace_id = azurerm_servicebus_namespace.this.id
}

# Topics in the namespace.
resource "azurerm_servicebus_topic" "this" {
  for_each = toset(var.topics)

  name         = each.value
  namespace_id = azurerm_servicebus_namespace.this.id
}

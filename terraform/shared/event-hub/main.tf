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
resource "azurerm_eventhub_namespace" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  capacity            = var.capacity
  tags                = var.tags

  # Secure defaults: TLS 1.2, no shared access keys (use Microsoft
  # Entra ID and RBAC) and no public network access. Data plane access
  # is via a private endpoint.
  minimum_tls_version           = "1.2"
  local_authentication_enabled  = false
  public_network_access_enabled = var.public_network_access_enabled
  auto_inflate_enabled          = var.auto_inflate_enabled
  maximum_throughput_units      = var.auto_inflate_enabled ? var.maximum_throughput_units : null

  identity {
    type = "SystemAssigned"
  }
}

# Event hubs in the namespace.
resource "azurerm_eventhub" "this" {
  for_each = var.event_hubs

  name              = each.key
  namespace_id      = azurerm_eventhub_namespace.this.id
  partition_count   = each.value.partition_count
  message_retention = each.value.message_retention
}

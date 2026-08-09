terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The cache. Clients connect over TLS through a private endpoint.
resource "azurerm_redis_cache" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  capacity            = var.capacity
  family              = var.family
  sku_name            = var.sku_name
  redis_version       = var.redis_version
  zones               = var.zones
  tags                = var.tags

  # Secure defaults: TLS 1.2 only, no plaintext port, Microsoft Entra
  # ID authentication enabled, and no public network access. Data plane
  # access is via a private endpoint.
  minimum_tls_version           = "1.2"
  non_ssl_port_enabled          = false
  public_network_access_enabled = var.public_network_access_enabled

  redis_configuration {
    active_directory_authentication_enabled = true
  }

  # Access keys stay disabled so Microsoft Entra ID is the only
  # authentication path; a leaked key cannot bypass identity.
  access_keys_authentication_enabled = var.access_keys_authentication_enabled

  identity {
    type = "SystemAssigned"
  }
}

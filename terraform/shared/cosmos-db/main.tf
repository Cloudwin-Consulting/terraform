terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The account. Access is with Microsoft Entra ID and the Cosmos DB
# data plane RBAC roles through a private endpoint.
resource "azurerm_cosmosdb_account" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  tags                = var.tags

  # Secure defaults: TLS 1.2, no key-based auth (use Microsoft Entra ID
  # and the data plane RBAC roles) and no public network access. Data
  # plane access is via private endpoints only.
  minimal_tls_version           = "Tls12"
  local_authentication_disabled = var.local_authentication_disabled
  public_network_access_enabled = var.public_network_access_enabled
  automatic_failover_enabled    = var.automatic_failover_enabled

  consistency_policy {
    consistency_level = var.consistency_level
  }

  geo_location {
    location          = var.location
    failover_priority = 0
    zone_redundant    = var.zone_redundant
  }

  # Secondary regions in failover priority order. Automatic failover
  # needs at least one of these to fail over to.
  dynamic "geo_location" {
    for_each = var.additional_geo_locations

    content {
      location          = geo_location.value.location
      failover_priority = geo_location.key + 1
      zone_redundant    = geo_location.value.zone_redundant
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

# SQL API databases. Containers are application-specific and created
# by the consuming stack.
resource "azurerm_cosmosdb_sql_database" "this" {
  for_each = toset(var.sql_databases)

  name                = each.value
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name
}

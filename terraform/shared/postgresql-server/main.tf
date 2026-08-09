terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A PostgreSQL flexible server. Deploy it into a delegated subnet with
# a privatelink.postgres.database.azure.com private DNS zone so it is
# only reachable inside the network; TLS is required by the platform.

data "azurerm_client_config" "current" {}

# The server. The authentication block enables Microsoft Entra ID
# sign-in alongside passwords.
resource "azurerm_postgresql_flexible_server" "this" {
  name                   = var.name
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = var.postgresql_version
  sku_name               = var.sku_name
  storage_mb             = var.storage_mb
  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password
  zone                   = var.zone
  tags                   = var.tags

  backup_retention_days         = var.backup_retention_days
  geo_redundant_backup_enabled  = var.geo_redundant_backup_enabled
  public_network_access_enabled = var.public_network_access_enabled

  delegated_subnet_id = var.delegated_subnet_id
  private_dns_zone_id = var.private_dns_zone_id

  authentication {
    active_directory_auth_enabled = var.entra_authentication_enabled
    password_auth_enabled         = true
    tenant_id                     = var.entra_authentication_enabled ? data.azurerm_client_config.current.tenant_id : null
  }

  dynamic "high_availability" {
    for_each = var.high_availability == null ? [] : [var.high_availability]

    content {
      mode                      = high_availability.value.mode
      standby_availability_zone = high_availability.value.standby_availability_zone
    }
  }
}

# The Microsoft Entra ID administrator that bootstraps database roles
# for other Entra principals.
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "this" {
  count = var.entra_administrator == null ? 0 : 1

  server_name         = azurerm_postgresql_flexible_server.this.name
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = var.entra_administrator.object_id
  principal_name      = var.entra_administrator.principal_name
  principal_type      = var.entra_administrator.principal_type
}

# Databases on the server, using the UTF8 character set.
resource "azurerm_postgresql_flexible_server_database" "this" {
  for_each = toset(var.databases)

  name      = each.value
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

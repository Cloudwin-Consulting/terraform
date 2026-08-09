terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A MySQL flexible server. Deploy it into a delegated subnet with a
# privatelink.mysql.database.azure.com private DNS zone so it is only
# reachable inside the network; TLS is required by the platform.

resource "azurerm_mysql_flexible_server" "this" {
  name                   = var.name
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = var.mysql_version
  sku_name               = var.sku_name
  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password
  zone                   = var.zone
  tags                   = var.tags

  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled

  # Secure default: no public network access. Use a delegated subnet
  # for private connectivity.
  public_network_access = var.public_network_access_enabled ? "Enabled" : "Disabled"

  delegated_subnet_id = var.delegated_subnet_id
  private_dns_zone_id = var.private_dns_zone_id

  dynamic "high_availability" {
    for_each = var.high_availability == null ? [] : [var.high_availability]

    content {
      mode                      = high_availability.value.mode
      standby_availability_zone = high_availability.value.standby_availability_zone
    }
  }
}

# Databases on the server, using the utf8mb4 character set.
resource "azurerm_mysql_flexible_database" "this" {
  for_each = toset(var.databases)

  name                = each.value
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.this.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

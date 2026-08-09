terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A SQL Managed Instance. The subnet must be delegated to
# Microsoft.Sql/managedInstances with the network intent policy's
# required network security group and route table attached. Deployment
# takes several hours.

data "azurerm_client_config" "current" {}

# The managed instance, joined to its delegated subnet.
resource "azurerm_mssql_managed_instance" "this" {
  name                         = var.name
  resource_group_name          = var.resource_group_name
  location                     = var.location
  subnet_id                    = var.subnet_id
  sku_name                     = var.sku_name
  vcores                       = var.vcores
  storage_size_in_gb           = var.storage_size_in_gb
  license_type                 = var.license_type
  collation                    = var.collation
  zone_redundant_enabled       = var.zone_redundant_enabled
  administrator_login          = var.administrator_login
  administrator_login_password = var.administrator_password
  tags                         = var.tags

  # Secure defaults: TLS 1.2 and no public data endpoint. Prefer
  # Microsoft Entra ID authentication through the administrator
  # resource below.
  minimum_tls_version          = "1.2"
  public_data_endpoint_enabled = false

  identity {
    type = "SystemAssigned"
  }
}

# The Microsoft Entra ID administrator. With Entra-only
# authentication the SQL administrator login cannot sign in.
resource "azurerm_mssql_managed_instance_active_directory_administrator" "this" {
  count = var.azuread_administrator == null ? 0 : 1

  managed_instance_id         = azurerm_mssql_managed_instance.this.id
  login_username              = var.azuread_administrator.login_username
  object_id                   = var.azuread_administrator.object_id
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  azuread_authentication_only = var.azuread_administrator.azuread_authentication_only
}

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The Log Analytics workspace.
resource "azurerm_log_analytics_workspace" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  retention_in_days   = var.retention_in_days
  daily_quota_gb      = var.daily_quota_gb
  tags                = var.tags

  # Secure defaults: no shared key authentication and no ingestion over the
  # public internet. Ingestion goes through an Azure Monitor Private Link
  # Scope. Queries remain available so the portal experience keeps working.
  local_authentication_enabled = false
  internet_ingestion_enabled   = var.internet_ingestion_enabled
  internet_query_enabled       = var.internet_query_enabled
}

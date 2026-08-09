terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The workspace-based Application Insights component.
resource "azurerm_application_insights" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  application_type    = var.application_type
  workspace_id        = var.log_analytics_workspace_id
  retention_in_days   = var.retention_in_days
  tags                = var.tags

  # Secure defaults: telemetry is authenticated with Microsoft Entra ID
  # rather than the instrumentation key alone, and ingestion over the
  # public internet is disabled - it goes through an Azure Monitor
  # Private Link Scope instead. Queries remain available so the portal
  # experience keeps working.
  local_authentication_disabled = var.local_authentication_disabled
  internet_ingestion_enabled    = var.internet_ingestion_enabled
  internet_query_enabled        = var.internet_query_enabled
}

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Core Azure Monitor alerting: an action group notifying operators by
# email, plus subscription-scoped activity log alerts for service
# health incidents and resource health degradation.

resource "azurerm_monitor_action_group" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  short_name          = var.action_group_short_name
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.email_receivers

    content {
      name                    = email_receiver.key
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

# Alerts on Azure service health incidents affecting the scope.
resource "azurerm_monitor_activity_log_alert" "service_health" {
  count = var.enable_service_health_alert ? 1 : 0

  name                = "${var.name}-service-health"
  resource_group_name = var.resource_group_name
  location            = "global"
  scopes              = [var.alert_scope_id]
  description         = "Service health incidents affecting the subscription."
  tags                = var.tags

  criteria {
    category = "ServiceHealth"
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

# Alerts when resources in the scope become degraded or unavailable.
resource "azurerm_monitor_activity_log_alert" "resource_health" {
  count = var.enable_resource_health_alert ? 1 : 0

  name                = "${var.name}-resource-health"
  resource_group_name = var.resource_group_name
  location            = "global"
  scopes              = [var.alert_scope_id]
  description         = "Resource health degradation in the subscription."
  tags                = var.tags

  criteria {
    category = "ResourceHealth"

    resource_health {
      current = ["Degraded", "Unavailable"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

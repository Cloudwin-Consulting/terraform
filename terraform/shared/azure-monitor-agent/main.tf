terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Installs the Azure Monitor Agent on a virtual machine and associates
# it with a data collection rule. The agent authenticates with the
# machine's system-assigned managed identity. Pass an existing rule via
# data_collection_rule_id, or pass log_analytics_workspace_id to create
# a default rule collecting logs and core performance counters. When the
# workspace ingests over private link only, also pass
# data_collection_endpoint_id so configuration and ingestion stay
# private.

locals {
  extension_type = var.os_type == "Linux" ? "AzureMonitorLinuxAgent" : "AzureMonitorWindowsAgent"

  data_collection_rule_id = coalesce(
    var.data_collection_rule_id,
    try(azurerm_monitor_data_collection_rule.this[0].id, null)
  )
}

# The agent extension. Without authentication settings the agent uses
# the machine's system-assigned managed identity.
resource "azurerm_virtual_machine_extension" "this" {
  name                       = local.extension_type
  virtual_machine_id         = var.virtual_machine_id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = local.extension_type
  type_handler_version       = var.type_handler_version
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = var.tags
}

# The default data collection rule: warning-and-above logs plus core
# performance counters, delivered to the workspace. Callers that create
# the workspace in the same apply must set create_data_collection_rule
# themselves, because the workspace ID is unknown until apply and cannot
# decide the count.
resource "azurerm_monitor_data_collection_rule" "this" {
  count = coalesce(var.create_data_collection_rule, var.data_collection_rule_id == null && var.log_analytics_workspace_id != null) ? 1 : 0

  name                        = var.data_collection_rule_name
  resource_group_name         = var.resource_group_name
  location                    = var.location
  kind                        = var.os_type
  data_collection_endpoint_id = var.data_collection_endpoint_id
  tags                        = var.tags

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace_id
      name                  = "log-analytics"
    }
  }

  data_flow {
    streams      = var.os_type == "Linux" ? ["Microsoft-Syslog", "Microsoft-Perf"] : ["Microsoft-Event", "Microsoft-Perf"]
    destinations = ["log-analytics"]
  }

  data_sources {
    dynamic "syslog" {
      for_each = var.os_type == "Linux" ? [1] : []

      content {
        name           = "syslog"
        streams        = ["Microsoft-Syslog"]
        facility_names = ["*"]
        log_levels     = ["Warning", "Error", "Critical", "Alert", "Emergency"]
      }
    }

    dynamic "windows_event_log" {
      for_each = var.os_type == "Windows" ? [1] : []

      content {
        name    = "eventlog"
        streams = ["Microsoft-Event"]
        x_path_queries = [
          "System!*[System[(Level=1 or Level=2 or Level=3)]]",
          "Application!*[System[(Level=1 or Level=2 or Level=3)]]",
        ]
      }
    }

    performance_counter {
      name                          = "perf"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor Information(_Total)\\% Processor Time",
        "\\Memory\\Available Bytes",
        "\\LogicalDisk(_Total)\\Free Megabytes",
      ]
    }
  }
}

# Attaches the data collection rule to the virtual machine.
resource "azurerm_monitor_data_collection_rule_association" "this" {
  name                    = "dcra-monitor-agent"
  target_resource_id      = var.virtual_machine_id
  data_collection_rule_id = local.data_collection_rule_id
}

# Points the agent at the data collection endpoint for configuration
# access. Azure requires this association to be named
# configurationAccessEndpoint. Callers that create the endpoint in the
# same apply must set associate_data_collection_endpoint themselves,
# because the endpoint ID is unknown until apply and cannot decide the
# count.
resource "azurerm_monitor_data_collection_rule_association" "endpoint" {
  count = coalesce(var.associate_data_collection_endpoint, var.data_collection_endpoint_id != null) ? 1 : 0

  name                        = "configurationAccessEndpoint"
  target_resource_id          = var.virtual_machine_id
  data_collection_endpoint_id = var.data_collection_endpoint_id
}

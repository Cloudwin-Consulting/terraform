terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# The container app with a system-assigned identity, optional
# user-assigned identities for registry pulls, and HTTPS-only ingress.
resource "azurerm_container_app" "this" {
  name                         = var.name
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = var.revision_mode
  workload_profile_name        = var.workload_profile_name
  tags                         = var.tags

  # Registry pulls need a user-assigned identity because the pull happens
  # before a system-assigned identity could be granted access.
  identity {
    type         = length(var.identity_ids) > 0 ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = var.identity_ids
  }

  dynamic "registry" {
    for_each = var.registries

    content {
      server   = registry.value.server
      identity = registry.value.identity
    }
  }

  # Ingress is only created when a target port is set. Insecure
  # connections are never served; HTTP is redirected to HTTPS.
  dynamic "ingress" {
    for_each = var.target_port == null ? [] : [1]

    content {
      external_enabled           = var.ingress_external_enabled
      target_port                = var.target_port
      transport                  = "auto"
      allow_insecure_connections = false

      traffic_weight {
        latest_revision = true
        percentage      = 100
      }
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = coalesce(var.container_name, var.name)
      image  = var.image
      cpu    = var.cpu
      memory = var.memory

      dynamic "env" {
        for_each = var.environment_variables

        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }
}

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}

  storage_use_azuread = true
  subscription_id     = var.deployment_subscription_id
}

# The application, hub and monitoring spokes may each live in their
# own subscription. Each aliased provider serves this stack's lookups
# in that spoke and defaults to the deployment subscription, keeping
# the single-subscription layout when the *_subscription_id variables
# stay null. Resources referencing what the lookups return (private
# endpoints, diagnostics, role assignments) carry full resource IDs,
# so they span subscriptions unchanged. The spoke stacks register
# their own subscriptions' resource providers, so these providers
# register none.
provider "azurerm" {
  alias = "app_spoke"

  features {}

  storage_use_azuread             = true
  subscription_id                 = coalesce(var.app_spoke_subscription_id, var.deployment_subscription_id)
  resource_provider_registrations = "none"
}

provider "azurerm" {
  alias = "hub"

  features {}

  storage_use_azuread             = true
  subscription_id                 = coalesce(var.hub_subscription_id, var.deployment_subscription_id)
  resource_provider_registrations = "none"
}

provider "azurerm" {
  alias = "monitoring"

  features {}

  storage_use_azuread             = true
  subscription_id                 = coalesce(var.monitoring_subscription_id, var.deployment_subscription_id)
  resource_provider_registrations = "none"
}

# The platform key vault holding this stack's secrets may sit outside
# the application spoke that owns the rest of the resources this stack
# references, so it is resolved through its own provider:
# platform_key_vault_subscription_id when set, otherwise the
# application spoke's subscription, otherwise the deployment
# subscription.
provider "azurerm" {
  alias = "key_vault"

  features {}

  storage_use_azuread             = true
  subscription_id                 = coalesce(var.platform_key_vault_subscription_id, var.app_spoke_subscription_id, var.deployment_subscription_id)
  resource_provider_registrations = "none"
}

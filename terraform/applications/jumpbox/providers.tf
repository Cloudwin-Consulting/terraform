terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}

  storage_use_azuread = true
  subscription_id     = var.deployment_subscription_id
}

# The hub may live in its own subscription. This aliased provider
# serves the stack's hub lookups and defaults to the deployment
# subscription, keeping the single-subscription layout when
# hub_subscription_id stays null. The hub stack registers its own
# subscription's resource providers, so this provider registers none.
provider "azurerm" {
  alias = "hub"

  features {}

  storage_use_azuread             = true
  subscription_id                 = coalesce(var.hub_subscription_id, var.deployment_subscription_id)
  resource_provider_registrations = "none"
}

# The platform key vault holding this stack's secrets may sit outside
# the hub that owns the rest of the resources this stack references,
# so it is resolved through its own provider:
# platform_key_vault_subscription_id when set, otherwise the hub's
# subscription, otherwise the deployment subscription.
provider "azurerm" {
  alias = "key_vault"

  features {}

  storage_use_azuread             = true
  subscription_id                 = coalesce(var.platform_key_vault_subscription_id, var.hub_subscription_id, var.deployment_subscription_id)
  resource_provider_registrations = "none"
}

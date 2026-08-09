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

# The application spoke may live in its own subscription. This aliased
# provider serves the stack's spoke lookups and defaults to the
# deployment subscription, keeping the single-subscription layout when
# app_spoke_subscription_id stays null. The spoke stack registers its
# own subscription's resource providers, so this provider registers
# none.
provider "azurerm" {
  alias = "app_spoke"

  features {}

  storage_use_azuread             = true
  subscription_id                 = coalesce(var.app_spoke_subscription_id, var.deployment_subscription_id)
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

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

# The monitoring spoke may live in its own subscription. The aliased
# provider serves this stack's workspace lookup there and defaults to
# the deployment subscription, keeping the single-subscription layout
# when monitoring_subscription_id stays null. Diagnostics reference the
# workspace by ID, which spans subscriptions on its own, so nothing
# else runs through this provider. The monitoring spoke registers its
# own subscription's resource providers, so this one registers none.
provider "azurerm" {
  alias = "monitoring"

  features {}

  storage_use_azuread             = true
  subscription_id                 = coalesce(var.monitoring_subscription_id, var.deployment_subscription_id)
  resource_provider_registrations = "none"
}

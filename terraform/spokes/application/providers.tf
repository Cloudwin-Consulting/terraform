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
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  storage_use_azuread = true
  subscription_id     = var.deployment_subscription_id
}

# The hub may live in its own subscription. This aliased provider serves
# every hub lookup and every resource this stack creates on the hub's
# side (its half of the peering, the DNS zone links); it defaults to the
# deployment subscription, preserving the single-subscription layout
# when hub_subscription_id stays null. The hub stack registers its own
# subscription's resource providers, so this provider registers none -
# the deployment identity only needs its resource permissions there.
provider "azurerm" {
  alias = "hub"

  features {}

  storage_use_azuread             = true
  subscription_id                 = coalesce(var.hub_subscription_id, var.deployment_subscription_id)
  resource_provider_registrations = "none"
}

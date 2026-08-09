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

# The hub and the application spoke may each live in their own
# subscription. These aliased providers serve every lookup in those
# stacks and every resource this stack creates on their side (their
# halves of the peerings, the hub's DNS zone links); each defaults to
# the deployment subscription, preserving the single-subscription
# layout when the *_subscription_id variables stay null. Those stacks
# register their own subscriptions' resource providers, so these
# providers register none - the deployment identity only needs its
# resource permissions there.
provider "azurerm" {
  alias = "hub"

  features {}

  storage_use_azuread             = true
  subscription_id                 = coalesce(var.hub_subscription_id, var.deployment_subscription_id)
  resource_provider_registrations = "none"
}

provider "azurerm" {
  alias = "app_spoke"

  features {}

  storage_use_azuread             = true
  subscription_id                 = coalesce(var.application_spoke_subscription_id, var.deployment_subscription_id)
  resource_provider_registrations = "none"
}

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

# This stack is deliberately self-contained: it deploys its own
# network, its own private DNS zones and its own monitoring into a
# single resource group, and looks nothing up in a hub, an application
# spoke or a monitoring spoke. It therefore needs one provider and no
# aliases - the whole application is one state file, one plan and one
# apply, which is what makes it straightforward to stand up again in
# another environment, subscription or region.
provider "azurerm" {
  features {}

  storage_use_azuread = true
  subscription_id     = var.deployment_subscription_id
}

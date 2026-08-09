terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
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

# Deploys the example workload into the cluster this stack creates,
# authenticating with the cluster credentials from the AKS module. The
# provider must be able to reach the API server whenever this stack
# plans or applies - with a private cluster that means an agent inside
# the network.
provider "kubernetes" {
  host                   = module.aks.host
  client_certificate     = base64decode(module.aks.client_certificate)
  client_key             = base64decode(module.aks.client_key)
  cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
}

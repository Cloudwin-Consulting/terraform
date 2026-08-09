locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  # The upstream stacks this one looks up derive their names the
  # same way, from their own workload name and this environment.
  hub_network_resource_group_name        = "rg-${var.hub_deployment_name}-${var.environment}-network"
  hub_virtual_network_name               = "vnet-${var.hub_deployment_name}-${var.environment}"
  platform_key_vault_name                = "kv-${var.hub_deployment_name}-${var.environment}"
  platform_key_vault_resource_group_name = "rg-${var.hub_deployment_name}-${var.environment}-secrets"

  resource_group_name = "rg-${local.name_suffix}"

  # The Environment tag holds the standard name of the environment,
  # while var.environment keeps the short form every resource name is
  # derived from - so the tag standard renames nothing.
  standard_environment_tags = {
    rd   = "RD"
    dev  = "Development"
    qa   = "QA"
    prod = "Production"
  }

  # The optional tags only join the set once they have a value, so no
  # resource carries an empty ExpiryDate, BusinessUnit or Repository.
  optional_tags = merge(
    var.expiry_date != null ? { ExpiryDate = var.expiry_date } : {},
    var.business_unit != null ? { BusinessUnit = var.business_unit } : {},
    var.repository != null ? { Repository = var.repository } : {},
  )

  # The tag set every resource in this stack carries: set on the
  # resources declared here and passed to every shared module, so
  # each resource is tagged in its own right rather than relying on
  # resource group tag inheritance. var.tags is merged last, so a
  # deployment can add to - or override - the standard values.
  common_tags = merge(
    {
      Application        = coalesce(var.application, var.deployment_name)
      Environment        = coalesce(var.environment_tag, lookup(local.standard_environment_tags, lower(var.environment), null))
      Owner              = var.owner
      CostCenter         = coalesce(var.cost_center, var.application, var.deployment_name)
      ManagedBy          = "Terraform"
      Criticality        = var.criticality
      Service            = var.service
      DataClassification = var.data_classification
      Lifecycle          = var.lifecycle_stage
    },
    local.optional_tags,
    var.tags,
  )
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.deployment_location
  tags     = local.common_tags
}

# ------------------------------------------------------------
# Existing platform resources: the hub's shared services subnet and
# its platform key vault. Deploying after the hub keeps the key vault
# reference out of the deployment that creates the vault.
# ------------------------------------------------------------

data "azurerm_subnet" "shared" {
  provider = azurerm.hub

  name                 = var.hub_shared_subnet_name
  virtual_network_name = local.hub_virtual_network_name
  resource_group_name  = local.hub_network_resource_group_name
}

data "azurerm_key_vault" "platform" {
  provider = azurerm.key_vault

  name                = coalesce(var.admin_ssh_public_key_key_vault_secret.key_vault_name, local.platform_key_vault_name)
  resource_group_name = coalesce(var.admin_ssh_public_key_key_vault_secret.key_vault_resource_group_name, local.platform_key_vault_resource_group_name)
}

# Reading the secret happens over the vault's private data plane, so
# the deployment agent must run inside the network (e.g. self-hosted).
data "azurerm_key_vault_secret" "admin_ssh_public_key" {
  provider = azurerm.key_vault

  name         = var.admin_ssh_public_key_key_vault_secret.secret_name
  key_vault_id = data.azurerm_key_vault.platform.id
}

# ------------------------------------------------------------
# Jump box - private management access, reached through Azure Bastion
# in the hub. SSH keys only; the public key comes from the hub's
# platform key vault, pre-loaded there before this stack deploys.
# ------------------------------------------------------------

module "virtual_machine" {
  source = "../../shared/virtual-machine"

  name                 = "vm-jump-${local.name_suffix}"
  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  subnet_id            = data.azurerm_subnet.shared.id
  size                 = var.virtual_machine_size
  admin_ssh_public_key = data.azurerm_key_vault_secret.admin_ssh_public_key.value
  tags                 = local.common_tags
}

locals {
  # Every resource name is derived from the workload and the
  # environment it is deployed into: <deployment_name>-<environment>.
  name_suffix = "${var.deployment_name}-${var.environment}"

  # The upstream stacks this one looks up derive their names the
  # same way, from their own workload name and this environment.
  app_spoke_network_resource_group_name = "rg-${var.app_spoke_deployment_name}-${var.environment}-network"
  app_spoke_virtual_network_name        = "vnet-${var.app_spoke_deployment_name}-${var.environment}"
  application_security_group_name       = var.application_security_group_role == null ? null : "asg-${var.app_spoke_deployment_name}-${var.environment}-${var.application_security_group_role}"

  platform_key_vault_name                = "kv-${var.app_spoke_deployment_name}-${var.environment}"
  platform_key_vault_resource_group_name = "rg-${var.app_spoke_deployment_name}-${var.environment}-secrets"

  resource_group_name = "rg-${local.name_suffix}"
  gallery_name        = coalesce(var.gallery_name, "gal${replace(local.name_suffix, "-", "")}")
  builder_name        = "vm-build-${local.name_suffix}"

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
# Existing platform resources: the application spoke network and its
# platform key vault.
# ------------------------------------------------------------

data "azurerm_subnet" "virtual_machines" {
  provider = azurerm.app_spoke

  name                 = var.virtual_machine_subnet_name
  virtual_network_name = local.app_spoke_virtual_network_name
  resource_group_name  = local.app_spoke_network_resource_group_name
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

data "azurerm_application_security_group" "this" {
  provider = azurerm.app_spoke

  count = local.application_security_group_name == null ? 0 : 1

  name                = local.application_security_group_name
  resource_group_name = local.app_spoke_network_resource_group_name
}

# ------------------------------------------------------------
# Compute gallery - the organisation's golden image catalogue. The VM
# stacks consume published versions through their source_image_id
# input, e.g. "<image_id>/versions/latest".
# ------------------------------------------------------------

module "compute_gallery" {
  source = "../../shared/compute-gallery"

  name                = local.gallery_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  description         = "Golden images baked by the ${local.name_suffix} builder."
  tags                = local.common_tags

  images = {
    ubuntu-server-hardened = {
      os_type            = "Linux"
      publisher          = var.image_publisher
      offer              = "ubuntu-server"
      sku                = "22-04-hardened"
      hyper_v_generation = "V2"
    }
  }
}

# ------------------------------------------------------------
# Builder virtual machine - the machine images are baked on. The
# preparation script runs through the Run Command service; capture the
# prepared machine into the gallery with `az vm deallocate`,
# `az vm generalize` and `az sig image-version create`, then rebuild
# or deallocate the builder until the next bake.
# ------------------------------------------------------------

module "builder" {
  source = "../../shared/virtual-machine"

  name                 = local.builder_name
  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  subnet_id            = data.azurerm_subnet.virtual_machines.id
  size                 = var.builder_size
  admin_ssh_public_key = data.azurerm_key_vault_secret.admin_ssh_public_key.value
  tags                 = local.common_tags

  application_security_group_ids = local.application_security_group_name == null ? [] : [data.azurerm_application_security_group.this[0].id]
}

# Prepares the builder for capture: patches the OS and installs the
# organisation's baseline tooling. Runs as a bash script from the
# repository - swap in script_uri to pull versioned build scripts from
# a storage account instead.
module "prepare_image" {
  source = "../../shared/virtual-machine-run-command"

  name               = "prepare-image"
  virtual_machine_id = module.builder.id
  location           = azurerm_resource_group.this.location
  tags               = local.common_tags

  script_content = file("${path.module}/scripts/prepare-image.sh")
}

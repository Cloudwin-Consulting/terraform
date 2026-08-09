terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A managed disk with private-only access and optional customer-managed
# key encryption through a disk encryption set. Attach it to a virtual
# machine from the calling module or stack.
resource "azurerm_managed_disk" "this" {
  name                 = var.name
  resource_group_name  = var.resource_group_name
  location             = var.location
  storage_account_type = var.storage_account_type
  create_option        = var.create_option
  disk_size_gb         = var.disk_size_gb
  zone                 = var.zone
  tier                 = var.tier
  tags                 = var.tags

  # Secure defaults: no access to the disk's data plane (exports and
  # SAS) from anywhere, and platform-managed keys unless a disk
  # encryption set is given.
  network_access_policy         = var.network_access_policy
  public_network_access_enabled = var.public_network_access_enabled
  disk_access_id                = var.disk_access_id
  disk_encryption_set_id        = var.disk_encryption_set_id
}

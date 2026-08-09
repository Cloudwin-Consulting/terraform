terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# A Windows Server virtual machine with no public IP address. Reach it
# over the private network, e.g. through Azure Bastion in the hub.

resource "azurerm_network_interface" "this" {
  name                = "${var.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

# Joins the network interface to the given application security groups,
# so subnet NSG rules can target this machine's workload by membership
# rather than IP address.
resource "azurerm_network_interface_application_security_group_association" "this" {
  count = length(var.application_security_group_ids)

  network_interface_id          = azurerm_network_interface.this.id
  application_security_group_id = var.application_security_group_ids[count.index]
}

# The virtual machine, reached over RDP through Azure Bastion.
resource "azurerm_windows_virtual_machine" "this" {
  name                = var.name
  computer_name       = var.computer_name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  tags                = var.tags

  network_interface_ids = [azurerm_network_interface.this.id]

  # Secure defaults: trusted launch and encryption at host. Encryption at
  # host requires the Microsoft.Compute/EncryptionAtHost feature to be
  # registered on the subscription.
  secure_boot_enabled        = var.secure_boot_enabled
  vtpm_enabled               = var.vtpm_enabled
  encryption_at_host_enabled = var.encryption_at_host_enabled
  patch_mode                 = var.patch_mode
  license_type               = var.license_type

  # The machine and its disks land in the given availability zone.
  zone = var.zone

  os_disk {
    caching                = var.os_disk.caching
    storage_account_type   = var.os_disk.storage_account_type
    disk_size_gb           = var.os_disk.disk_size_gb
    disk_encryption_set_id = var.os_disk.disk_encryption_set_id
  }

  # The machine boots from a compute gallery image when source_image_id
  # is set, otherwise from the marketplace image reference.
  source_image_id = var.source_image_id

  dynamic "source_image_reference" {
    for_each = var.source_image_id == null ? [1] : []

    content {
      publisher = var.source_image_reference.publisher
      offer     = var.source_image_reference.offer
      sku       = var.source_image_reference.sku
      version   = var.source_image_reference.version
    }
  }

  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {}
}

# Protects the virtual machine with the given Recovery Services
# vault backup policy.
resource "azurerm_backup_protected_vm" "this" {
  count = var.backup == null ? 0 : 1

  resource_group_name = var.backup.recovery_vault_resource_group_name
  recovery_vault_name = var.backup.recovery_vault_name
  source_vm_id        = azurerm_windows_virtual_machine.this.id
  backup_policy_id    = var.backup.backup_policy_id
}

# Installs the Azure Monitor Agent and its data collection rule
# association.
module "monitor_agent" {
  source = "../azure-monitor-agent"

  count = var.monitor_agent == null ? 0 : 1

  virtual_machine_id          = azurerm_windows_virtual_machine.this.id
  os_type                     = "Windows"
  data_collection_rule_id     = var.monitor_agent.data_collection_rule_id
  log_analytics_workspace_id  = var.monitor_agent.log_analytics_workspace_id
  data_collection_endpoint_id = var.monitor_agent.data_collection_endpoint_id
  data_collection_rule_name   = "dcr-${var.name}"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  tags                        = var.tags

  create_data_collection_rule        = var.monitor_agent.create_data_collection_rule
  associate_data_collection_endpoint = var.monitor_agent.associate_data_collection_endpoint
}

# Managed data disks from the managed-disk module, following the
# machine's availability zone.
module "data_disk" {
  source = "../managed-disk"

  for_each = { for disk in var.data_disks : disk.name => disk }

  name                          = each.value.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  disk_size_gb                  = each.value.disk_size_gb
  storage_account_type          = each.value.storage_account_type
  zone                          = var.zone
  tier                          = each.value.tier
  disk_encryption_set_id        = each.value.disk_encryption_set_id
  network_access_policy         = each.value.network_access_policy
  public_network_access_enabled = each.value.public_network_access_enabled
  disk_access_id                = each.value.disk_access_id
  tags                          = var.tags
}

# Attaches the data disks in the order given, using the list index as
# the LUN.
resource "azurerm_virtual_machine_data_disk_attachment" "this" {
  for_each = { for index, disk in var.data_disks : disk.name => merge(disk, { lun = index }) }

  managed_disk_id    = module.data_disk[each.key].id
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  lun                = each.value.lun
  caching            = each.value.caching
}

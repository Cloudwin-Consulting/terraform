terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# An Azure Virtual Desktop session host: a Windows multi-session
# machine from the windows-virtual-machine module, joined to Microsoft
# Entra ID and registered into a host pool. The machine has no public
# IP address and nothing listens for inbound connections - users reach
# it through the AVD reverse connect transport, which the host dials
# out to over HTTPS. The admin account is break-glass only: users sign
# in with their Microsoft Entra credentials, authorised by the Virtual
# Machine User Login role on the machine's scope.
module "virtual_machine" {
  source = "../windows-virtual-machine"

  name                = var.name
  computer_name       = var.computer_name
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id
  size                = var.size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  tags                = var.tags

  application_security_group_ids = var.application_security_group_ids

  zone    = var.zone
  os_disk = var.os_disk

  source_image_id            = var.source_image_id
  source_image_reference     = var.source_image_reference
  license_type               = var.license_type
  secure_boot_enabled        = var.secure_boot_enabled
  vtpm_enabled               = var.vtpm_enabled
  encryption_at_host_enabled = var.encryption_at_host_enabled

  monitor_agent = var.monitor_agent
}

# Changing where or how the machine registers - the host pool or the
# agent package - must re-run registration with a token current at
# that apply, never with the stale token pinned in state below, so
# those inputs re-create the extension instead of updating it.
#
# The pool's ID covers the case its name cannot: switching a pool
# between Pooled and Personal replaces it under the same derived name,
# so the name alone would not change and the hosts would stay
# registered against the pool that was destroyed. A replaced pool's ID
# is unknown at plan time, which re-creates this resource and, through
# it, the extension.
resource "terraform_data" "registration_inputs" {
  triggers_replace = [var.host_pool_id, var.host_pool_name, var.avd_agent_package_url]
}

# Joins the machine to Microsoft Entra ID with its system-assigned
# managed identity. This runs before the machine registers with the
# host pool, so the pool receives a host the directory already knows.
# Set intune_mdm_id to also enrol the machine into Intune.
resource "azurerm_virtual_machine_extension" "entra_join" {
  name                       = "AADLoginForWindows"
  virtual_machine_id         = module.virtual_machine.id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true
  tags                       = var.tags

  settings = var.intune_mdm_id == null ? null : jsonencode({
    mdmId = var.intune_mdm_id
  })
}

# Registers the machine into the host pool, after it has joined
# Microsoft Entra ID: the AddSessionHost configuration below runs with
# aadJoin set, so the agent registers a host that is already joined -
# registering first would report a host the directory does not yet
# know, leaving it unavailable in the pool.
#
# The DSC extension pulls the AVD agent configuration package and runs
# its AddSessionHost configuration with the pool's token. The token rotates
# (the avd-host-pool module re-issues it as it expires), so changes to
# protected_settings are ignored - a registered host stays registered,
# and only hosts created later use the newer token. Re-registration
# (a new host pool or agent package) is a replacement, which sends the
# current token.
resource "azurerm_virtual_machine_extension" "session_host_registration" {
  name                       = "AvdSessionHostRegistration"
  virtual_machine_id         = module.virtual_machine.id
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.73"
  auto_upgrade_minor_version = true
  tags                       = var.tags

  settings = jsonencode({
    modulesUrl            = var.avd_agent_package_url
    configurationFunction = "Configuration.ps1\\AddSessionHost"
    properties = {
      HostPoolName = var.host_pool_name
      aadJoin      = true
    }
  })

  protected_settings = jsonencode({
    properties = {
      registrationInfoToken = var.registration_token
    }
  })

  lifecycle {
    ignore_changes       = [protected_settings]
    replace_triggered_by = [terraform_data.registration_inputs]
  }

  depends_on = [azurerm_virtual_machine_extension.entra_join]
}


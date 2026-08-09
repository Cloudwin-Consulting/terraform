terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Runs a script on a deployed virtual machine through the Azure Run
# Command service, without opening any inbound network path to the
# machine. On Windows the script runs as PowerShell under SYSTEM; on
# Linux it runs under the default shell (start the script with a
# shebang such as #!/usr/bin/env python3 to use another interpreter).
#
# The script comes from exactly one of:
#   - script_content: the script text, e.g. file("${path.module}/scripts/x.ps1")
#     for a script kept in the repository.
#   - script_uri: a URL the machine downloads the script from, with
#     optional managed identity authentication for private storage.
#
# Values in protected_parameters (for example credentials read from the
# platform key vault) are delivered to the machine encrypted and never
# appear in instance view, logs or the Azure portal.
resource "azurerm_virtual_machine_run_command" "this" {
  name               = var.name
  virtual_machine_id = var.virtual_machine_id
  location           = var.location
  tags               = var.tags

  source {
    script     = var.script_content
    script_uri = var.script_uri

    dynamic "script_uri_managed_identity" {
      for_each = var.script_uri_managed_identity == null ? [] : [var.script_uri_managed_identity]

      content {
        client_id = script_uri_managed_identity.value.client_id
        object_id = script_uri_managed_identity.value.object_id
      }
    }
  }

  dynamic "parameter" {
    for_each = var.parameters

    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  # A dynamic block cannot iterate a sensitive collection, so this
  # iterates the parameter names and reads each value from the sensitive
  # map: the names are not secret, the values stay sensitive.
  dynamic "protected_parameter" {
    for_each = nonsensitive(toset(keys(var.protected_parameters)))

    content {
      name  = protected_parameter.value
      value = var.protected_parameters[protected_parameter.value]
    }
  }

  run_as_user     = var.run_as_user
  run_as_password = var.run_as_password

  output_blob_uri = var.output_blob_uri
  error_blob_uri  = var.error_blob_uri
}

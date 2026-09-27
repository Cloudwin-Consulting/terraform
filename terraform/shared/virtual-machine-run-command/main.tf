terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

locals {
  # Named by position and file name, so the order shows in the output
  # and two files with the same name from different folders cannot
  # overwrite each other on the machine.
  script_files = [
    for index, path in var.script_files : {
      name    = format("%02d-%s", index + 1, replace(basename(path), "/[^A-Za-z0-9._-]/", "_"))
      content = filebase64(path)
    }
  ]

  script_files_windows = length(var.script_files) > 0 && alltrue([
    for path in var.script_files : endswith(lower(path), ".ps1")
  ])

  # The launcher declares the parameter names, never their values, so
  # the names can come out from behind the sensitive map.
  parameter_names = sort(distinct(concat(
    keys(var.parameters),
    nonsensitive(keys(var.protected_parameters)),
  )))

  script = length(var.script_files) == 0 ? var.script_content : (
    local.script_files_windows
    ? templatefile("${path.module}/templates/run-script-files.ps1.tftpl", {
      scripts         = local.script_files
      parameter_names = local.parameter_names
    })
    : templatefile("${path.module}/templates/run-script-files.sh.tftpl", {
      scripts = local.script_files
    })
  )
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
#   - script_files: paths to one or more script files in the repository,
#     run one after another in the order given - all .sh for a Linux
#     machine, or all .ps1 for a Windows one.
#   - script_uri: a URL the machine downloads the script from, with
#     optional managed identity authentication for private storage.
#
# Azure runs separate run commands on the same machine at the same
# time, and Terraform cannot chain the instances of one resource, so
# script_files are not given a run command each. The module instead
# reads the files itself and generates a single launcher script (see
# templates/) that carries them, writes them to a private directory on
# the machine and runs them in order, each in its own process, stopping
# at the first failure. The caller passes plain file paths - there is
# nothing to read, join or encode on its side:
#
#   script_files = [
#     "${path.module}/scripts/install-agent.ps1",
#     "${path.module}/scripts/configure-app.ps1",
#   ]
#
# or, for every script in a folder in name order:
#
#   script_files = [
#     for f in sort(fileset("${path.module}/scripts/setup", "*.sh")) :
#     "${path.module}/scripts/setup/${f}"
#   ]
#
# Every script receives the run command's parameters as it would on its
# own: on Linux as environment variables (and nameless parameters as
# positional arguments); on Windows as named arguments, each script
# getting those its param() block declares. Changing any file reruns
# the whole sequence, so each script must be safe to run again, and a
# script that restarts the machine must come last. The files travel
# inline in the run command, so keep large payloads (installers, big
# data files) in storage and use script_uri or download them from a
# script instead.
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
    script     = local.script
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

  lifecycle {
    precondition {
      condition = !local.script_files_windows || alltrue([
        for name in local.parameter_names : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", name))
      ])
      error_message = "With .ps1 script_files, every parameter and protected parameter needs a name that is a valid PowerShell parameter name."
    }
  }
}

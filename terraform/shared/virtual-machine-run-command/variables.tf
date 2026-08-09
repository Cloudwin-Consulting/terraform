variable "name" {
  description = "The name of the run command resource on the virtual machine."
  type        = string
}

variable "virtual_machine_id" {
  description = "The ID of the virtual machine the script runs on."
  type        = string
}

variable "location" {
  description = "The Azure location of the virtual machine."
  type        = string
}

variable "script_content" {
  description = "The script to run, e.g. loaded from the repository with file(). Exactly one of script_content and script_uri must be set."
  type        = string
  default     = null

  validation {
    condition     = (var.script_content == null) != (var.script_uri == null)
    error_message = "Set exactly one of script_content and script_uri as the script source."
  }
}

variable "script_uri" {
  description = "A URL the machine downloads the script from, e.g. a storage account blob. Use script_uri_managed_identity for private storage."
  type        = string
  default     = null
}

variable "script_uri_managed_identity" {
  description = "The managed identity the machine authenticates to script_uri with, for scripts in private storage. Set client_id or object_id of an identity assigned to the machine with Storage Blob Data Reader on the container. Leave null for publicly reachable URIs."
  type = object({
    client_id = optional(string)
    object_id = optional(string)
  })
  default = null

  validation {
    condition     = var.script_uri_managed_identity == null || var.script_uri != null
    error_message = "script_uri_managed_identity is only used with script_uri."
  }

  validation {
    condition = (
      var.script_uri_managed_identity == null ||
      (try(var.script_uri_managed_identity.client_id, null) != null) != (try(var.script_uri_managed_identity.object_id, null) != null)
    )
    error_message = "script_uri_managed_identity needs exactly one of client_id or object_id."
  }
}

variable "parameters" {
  description = "Parameters passed to the script by name, e.g. a domain name for a domain joining script."
  type        = map(string)
  default     = {}
}

variable "protected_parameters" {
  description = "Sensitive parameters passed to the script by name, e.g. credentials read from the platform key vault. Delivered encrypted and never shown in instance view or logs."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "run_as_user" {
  description = "The user the script runs as on the machine. Leave null for the platform default (SYSTEM on Windows, root on Linux)."
  type        = string
  default     = null
}

variable "run_as_password" {
  description = "The password of run_as_user, e.g. read from the platform key vault. Only needed on Windows when run_as_user is set."
  type        = string
  default     = null
  sensitive   = true
}

variable "output_blob_uri" {
  description = "A SAS-authenticated blob URI the script's standard output is uploaded to. Leave null to keep output in instance view only."
  type        = string
  default     = null
}

variable "error_blob_uri" {
  description = "A SAS-authenticated blob URI the script's standard error is uploaded to. Leave null to keep errors in instance view only."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the run command resource."
  type        = map(string)
  default     = {}
}

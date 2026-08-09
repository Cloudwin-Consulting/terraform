terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Standing RBAC role assignments: one role at one scope, granted to
# each of the supplied principals. Principals are keyed by a static
# label rather than by object ID, so identities created in the same
# apply - whose object IDs are unknown at plan time - can still be
# granted roles.
resource "azurerm_role_assignment" "this" {
  for_each = var.principals

  scope                            = var.scope
  role_definition_name             = var.role_definition_name
  role_definition_id               = var.role_definition_id
  principal_id                     = each.value
  principal_type                   = var.principal_type
  description                      = var.description
  condition                        = var.condition
  condition_version                = var.condition_version
  skip_service_principal_aad_check = var.skip_service_principal_aad_check
}

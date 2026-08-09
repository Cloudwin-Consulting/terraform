terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# An Azure Compute Gallery with image definitions. Image versions are
# published by build tooling (e.g. Packer or Azure Image Builder);
# virtual machines consume them through the virtual machine modules'
# source_image_id variable.

resource "azurerm_shared_image_gallery" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = var.description
  tags                = var.tags
}

# Image definitions in the gallery. Versions are published by build
# tooling.
resource "azurerm_shared_image" "this" {
  for_each = var.images

  name                = each.key
  gallery_name        = azurerm_shared_image_gallery.this.name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = each.value.os_type
  hyper_v_generation  = each.value.hyper_v_generation
  architecture        = each.value.architecture

  # Matches the trusted launch defaults of the virtual machine modules.
  trusted_launch_supported = each.value.trusted_launch_supported

  identifier {
    publisher = each.value.publisher
    offer     = each.value.offer
    sku       = each.value.sku
  }

  tags = var.tags
}

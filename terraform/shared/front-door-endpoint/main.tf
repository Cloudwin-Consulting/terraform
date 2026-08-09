terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# An endpoint on an existing Front Door profile with a single origin
# group, origin and route. When private_link is set the origin is
# reached over Private Link, so it can keep public network access
# disabled; the target resource's pending private endpoint connection
# must be approved after deployment.
#
# The origin leg defaults to HTTPS end to end. An origin that
# terminates no TLS of its own - e.g. a plain-HTTP Kubernetes service
# behind a private link service - needs origin_forwarding_protocol and
# health_probe_protocol set to their Http variants, which leaves that
# leg unencrypted (on the Microsoft backbone, and private when Private
# Link carries it, but not TLS). Terminating TLS at the origin is the
# stronger posture wherever the origin can do it.

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = var.name
  cdn_frontdoor_profile_id = var.front_door_profile_id
  tags                     = var.tags
}

# The origin group with its health probe and load balancing settings.
resource "azurerm_cdn_frontdoor_origin_group" "this" {
  name                     = "${var.name}-origins"
  cdn_frontdoor_profile_id = var.front_door_profile_id
  session_affinity_enabled = false

  health_probe {
    protocol            = var.health_probe_protocol
    interval_in_seconds = 100
    request_type        = "HEAD"
    path                = var.health_probe_path
  }

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
  }
}

# The origin, optionally reached over Private Link so it can keep
# public network access disabled.
resource "azurerm_cdn_frontdoor_origin" "this" {
  name                           = "${var.name}-origin"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.this.id
  enabled                        = true
  host_name                      = var.origin_host_name
  origin_host_header             = var.origin_host_name
  http_port                      = var.origin_http_port
  https_port                     = var.origin_https_port
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = var.certificate_name_check_enabled

  # target_type names the subresource of a PaaS origin, e.g. sites for a
  # web app. A private link service origin publishes a load balancer
  # rather than a subresource, so it leaves target_type unset.
  dynamic "private_link" {
    for_each = var.private_link == null ? [] : [var.private_link]

    content {
      request_message        = "Front Door private link origin"
      target_type            = private_link.value.target_type
      location               = private_link.value.location
      private_link_target_id = private_link.value.target_id
    }
  }
}

# The route binding the endpoint to the origin group.
resource "azurerm_cdn_frontdoor_route" "this" {
  name                          = "${var.name}-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.this.id]
  enabled                       = true

  # Clients always arrive over HTTPS - HTTP requests are redirected -
  # and the origin leg follows origin_forwarding_protocol, HTTPS by
  # default.
  supported_protocols    = ["Http", "Https"]
  https_redirect_enabled = true
  forwarding_protocol    = var.origin_forwarding_protocol
  patterns_to_match      = ["/*"]
  link_to_default_domain = true
}

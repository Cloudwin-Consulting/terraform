terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# An Application Gateway v2 with a single listener, backend pool and
# routing rule. The listener binds to the private frontend, so traffic
# enters over the internal network; the public frontend exists because
# the v2 SKU requires one but nothing listens on it. Without a
# certificate the listener is plain HTTP - pass
# ssl_certificate_key_vault_secret_id (and a user-assigned identity
# that can read it) to terminate TLS.
#
# The backend pool holds either hostnames (backend_fqdns, e.g. web app
# default hostnames) or addresses (backend_ip_addresses, e.g. a
# Kubernetes internal load balancer frontend, which has no name of its
# own).

locals {
  listener_protocol = var.ssl_certificate_key_vault_secret_id == null ? "Http" : "Https"
  listener_port     = var.ssl_certificate_key_vault_secret_id == null ? 80 : 443

  # An FQDN backend carries a hostname the gateway can take the host
  # header from; an address does not. backend_host_name overrides both,
  # for backends that expect a particular host.
  backend_pick_host_name = var.backend_host_name == null && length(var.backend_ip_addresses) == 0

  backend_probe_protocol = coalesce(var.backend_probe_protocol, var.backend_protocol)

  # The probe borrows its host from the backend settings whenever they
  # have one to lend. With an address-based pool and no backend_host_name
  # they have none, so the probe names the first backend address itself -
  # Azure rejects a probe with neither.
  backend_probe_host = (
    local.backend_pick_host_name || var.backend_host_name != null
    ? null
    : try(var.backend_ip_addresses[0], null)
  )
}

# The public IP the v2 SKU requires. No listener binds to it.
resource "azurerm_public_ip" "this" {
  name                = "${var.name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  tags                = var.tags
}

# The gateway with a single private listener, backend pool, health
# probe and routing rule.
resource "azurerm_application_gateway" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  zones               = var.zones
  tags                = var.tags

  sku {
    name = var.sku_name
    tier = var.sku_tier
  }

  autoscale_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  dynamic "identity" {
    for_each = length(var.identity_ids) > 0 ? [1] : []

    content {
      type         = "UserAssigned"
      identity_ids = var.identity_ids
    }
  }

  gateway_ip_configuration {
    name      = "gateway"
    subnet_id = var.subnet_id
  }

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.this.id
  }

  frontend_ip_configuration {
    name                          = "private"
    subnet_id                     = var.subnet_id
    private_ip_address            = var.private_ip_address
    private_ip_address_allocation = "Static"
  }

  frontend_port {
    name = "listener"
    port = local.listener_port
  }

  dynamic "ssl_certificate" {
    for_each = var.ssl_certificate_key_vault_secret_id == null ? [] : [1]

    content {
      name                = "listener"
      key_vault_secret_id = var.ssl_certificate_key_vault_secret_id
    }
  }

  http_listener {
    name                           = "listener"
    frontend_ip_configuration_name = "private"
    frontend_port_name             = "listener"
    protocol                       = local.listener_protocol
    ssl_certificate_name           = var.ssl_certificate_key_vault_secret_id == null ? null : "listener"
  }

  probe {
    name                                      = "backend"
    protocol                                  = local.backend_probe_protocol
    host                                      = local.backend_probe_host
    path                                      = var.backend_probe_path
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = local.backend_probe_host == null
  }

  backend_address_pool {
    name         = "backend"
    fqdns        = var.backend_fqdns
    ip_addresses = var.backend_ip_addresses
  }

  backend_http_settings {
    name                                = "backend"
    protocol                            = var.backend_protocol
    port                                = var.backend_port
    host_name                           = var.backend_host_name
    cookie_based_affinity               = "Disabled"
    pick_host_name_from_backend_address = local.backend_pick_host_name
    request_timeout                     = 30
    probe_name                          = "backend"
  }

  request_routing_rule {
    name                       = "default"
    priority                   = 100
    rule_type                  = "Basic"
    http_listener_name         = "listener"
    backend_address_pool_name  = "backend"
    backend_http_settings_name = "backend"
  }

  dynamic "waf_configuration" {
    for_each = var.sku_tier == "WAF_v2" ? [1] : []

    content {
      enabled          = true
      firewall_mode    = var.waf_mode
      rule_set_type    = "OWASP"
      rule_set_version = "3.2"
    }
  }
}

# Sends logs and metrics to Log Analytics when a workspace is
# configured. Callers that create the workspace in the same apply must
# set enable_diagnostics themselves, because the workspace ID is unknown
# until apply and cannot decide the count.
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = coalesce(var.enable_diagnostics, var.log_analytics_workspace_id != null) ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_application_gateway.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

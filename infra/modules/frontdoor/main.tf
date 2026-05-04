resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = var.front_door_name
  resource_group_name = var.resource_group_name
  sku_name            = var.sku
  tags                = var.tags

  response_timeout_seconds = 60

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = "${var.front_door_name}-ep"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  enabled                  = true
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "mcp" {
  name                     = "mcp-origins"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  session_affinity_enabled = false

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }

  health_probe {
    path                = "/health"
    request_type        = "GET"
    protocol            = "Https"
    interval_in_seconds = 30
  }
}

resource "azurerm_cdn_frontdoor_origin" "primary" {
  name                          = "primary"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.mcp.id

  host_name                      = var.primary_origin_host_name
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = var.primary_origin_host_name
  priority                       = 1
  weight                         = 1000
  enabled                        = true
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_origin" "secondary" {
  count = var.secondary_origin_host_name == "" ? 0 : 1

  name                          = "secondary"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.mcp.id

  host_name                      = var.secondary_origin_host_name
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = var.secondary_origin_host_name
  priority                       = 2
  weight                         = 1000
  enabled                        = true
  certificate_name_check_enabled = true

  depends_on = [azurerm_cdn_frontdoor_origin.primary]
}

resource "azurerm_cdn_frontdoor_route" "mcp" {
  name                          = "mcp-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.mcp.id
  cdn_frontdoor_origin_ids      = concat([azurerm_cdn_frontdoor_origin.primary.id], azurerm_cdn_frontdoor_origin.secondary[*].id)
  supported_protocols           = ["Https"]
  patterns_to_match             = ["/*"]
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = true
  link_to_default_domain        = true
  enabled                       = true
}

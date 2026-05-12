module "frontdoor" {
  source = "./modules/frontdoor"
  count  = (local.enable_dr && !var.use_existing_front_door) ? 1 : 0

  resource_group_name        = azurerm_resource_group.primary.name
  front_door_name            = local.names.front_door
  sku                        = var.front_door_sku
  tags                       = local.tags
  primary_origin_host_name   = module.appservice.default_host_name
  secondary_origin_host_name = module.secondary[0].app_service_host_name
}

# ---------------------------------------------------------------------------
# Existing Front Door lookup (DR + reuse path).
#
# When DR is enabled and use_existing_front_door=true, Terraform skips
# creating the AFD profile / endpoint / origin group / origins / route, and
# reads the existing profile + endpoint to populate MCP_SERVER_BASE_URL and
# the FDID app-setting binding. Routing, origin groups, and origins on the
# referenced profile must be managed out-of-band.
# ---------------------------------------------------------------------------
data "azurerm_cdn_frontdoor_profile" "existing" {
  count               = (local.enable_dr && var.use_existing_front_door) ? 1 : 0
  name                = coalesce(var.existing_front_door_profile_name, local.names.front_door)
  resource_group_name = coalesce(var.existing_front_door_resource_group_name, azurerm_resource_group.primary.name)
}

data "azurerm_cdn_frontdoor_endpoint" "existing" {
  count               = (local.enable_dr && var.use_existing_front_door) ? 1 : 0
  name                = coalesce(var.existing_front_door_endpoint_name, "${data.azurerm_cdn_frontdoor_profile.existing[0].name}-ep")
  profile_name        = data.azurerm_cdn_frontdoor_profile.existing[0].name
  resource_group_name = data.azurerm_cdn_frontdoor_profile.existing[0].resource_group_name
}

locals {
  front_door_endpoint_url = (
    !local.enable_dr ? "" :
    var.use_existing_front_door
    ? "https://${data.azurerm_cdn_frontdoor_endpoint.existing[0].host_name}"
    : module.frontdoor[0].endpoint_url
  )
  front_door_id_header = (
    !local.enable_dr ? "" :
    var.use_existing_front_door
    ? data.azurerm_cdn_frontdoor_profile.existing[0].resource_guid
    : module.frontdoor[0].front_door_id_header
  )
}

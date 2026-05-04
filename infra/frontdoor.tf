module "frontdoor" {
  source = "./modules/frontdoor"
  count  = local.enable_dr ? 1 : 0

  resource_group_name        = azurerm_resource_group.primary.name
  front_door_name            = local.names.front_door
  sku                        = var.front_door_sku
  tags                       = local.tags
  primary_origin_host_name   = module.appservice.default_host_name
  secondary_origin_host_name = module.secondary[0].app_service_host_name
}

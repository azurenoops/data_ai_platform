module "secondary" {
  source = "./modules/regional"
  count  = local.enable_dr ? 1 : 0

  providers = {
    azurerm = azurerm
    azapi   = azapi
  }

  resource_group_name                         = azurerm_resource_group.dr[0].name
  location                                    = var.secondary_location
  tags                                        = local.tags
  resource_token                              = local.resource_token
  abbrs                                       = local.abbrs
  search_sku                                  = var.search_sku
  app_service_plan_sku                        = var.app_service_plan_sku
  mcp_public_network_access_enabled           = var.mcp_public_network_access_enabled
  app_insights_connection_string              = module.monitoring.app_insights_connection_string
  mcp_server_user_assigned_identity_id        = module.identity.mcp_server_identity_id
  mcp_server_user_assigned_identity_client_id = module.identity.mcp_server_identity_client_id
  ingestion_user_assigned_identity_id         = module.identity.ingestion_identity_id
  ingestion_user_assigned_identity_client_id  = module.identity.ingestion_identity_client_id
  tenant_id                                   = data.azurerm_client_config.current.tenant_id
  primary_storage_account_name                = module.storage.storage_account_name
  app_audience                                = local.app_audience
  chat_deployment                             = var.chat_deployment
  chat_mini_deployment                        = var.chat_mini_deployment
  embedding_deployment                        = var.embedding_deployment
  cmk_key_uri                                 = local.cmk_key_uri
  cmk_user_assigned_identity_id               = local.cmk_user_assigned_identity_id
  cmk_user_assigned_identity_client_id        = local.cmk_user_assigned_identity_client_id
  cmk_key_name                                = local.cmk_key_name
  cmk_key_vault_uri                           = local.cmk_key_vault_uri
  storage_sku                                 = "Standard_RAGZRS"
}

# Cross-region role assignments: ingestion + MCP UAMIs need access to the secondary regional resources.
module "secondary_roles" {
  source = "./modules/roleassignments"
  count  = local.enable_dr ? 1 : 0

  storage_account_id               = module.secondary[0].storage_account_id
  search_id                        = module.secondary[0].search_id
  foundry_account_id               = module.secondary[0].foundry_account_id
  document_intelligence_account_id = module.secondary[0].document_intelligence_account_id
  key_vault_id                     = module.keyvault.key_vault_id
  mcp_server_principal_id          = module.identity.mcp_server_principal_id
  ingestion_principal_id           = module.identity.ingestion_principal_id
  data_factory_principal_id        = module.identity.data_factory_principal_id
  dev_principal_id                 = var.principal_id
  cmk_consumer_principal_ids = var.enable_cmk ? [
    module.secondary[0].search_principal_id,
  ] : []
}

module "roles" {
  source = "./modules/roleassignments"

  storage_account_id               = module.storage.storage_id
  search_id                        = local.search_id
  foundry_account_id               = local.foundry_account_id
  document_intelligence_account_id = module.document_intelligence.account_id
  key_vault_id                     = module.keyvault.key_vault_id
  mcp_server_principal_id          = module.identity.mcp_server_principal_id
  ingestion_principal_id           = module.identity.ingestion_principal_id
  data_factory_principal_id        = module.identity.data_factory_principal_id
  enable_data_factory_pipelines    = var.enable_data_factory_pipelines
  dev_principal_id                 = var.principal_id
  cmk_consumer_principal_ids = var.enable_cmk ? compact([
    local.search_principal_id,
  ]) : []
}

resource "azurerm_role_assignment" "portal_storage_writer" {
  scope              = module.storage.storage_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe"
  principal_id       = module.identity.portal_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "portal_data_factory_contributor" {
  scope              = local.data_factory_id
  role_definition_id = "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/673868aa-7521-48a0-acc6-0f60742d39f5"
  principal_id       = module.identity.portal_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_cosmosdb_sql_role_assignment" "ingestion_source_config_contributor" {
  resource_group_name = azurerm_resource_group.primary.name
  account_name        = module.cosmosdb.account_name
  role_definition_id  = "${module.cosmosdb.account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = module.identity.ingestion_principal_id
  scope               = module.cosmosdb.account_id
}

resource "azurerm_cosmosdb_sql_role_assignment" "portal_source_config_contributor" {
  resource_group_name = azurerm_resource_group.primary.name
  account_name        = module.cosmosdb.account_name
  role_definition_id  = "${module.cosmosdb.account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = module.identity.portal_principal_id
  scope               = module.cosmosdb.account_id
}

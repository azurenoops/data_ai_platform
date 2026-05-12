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

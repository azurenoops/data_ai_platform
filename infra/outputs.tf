output "AZURE_LOCATION" {
  value = var.location
}

output "AZURE_TENANT_ID" {
  value = data.azurerm_client_config.current.tenant_id
}

output "AZURE_RESOURCE_GROUP" {
  value = azurerm_resource_group.primary.name
}

output "STORAGE_ACCOUNT_NAME" {
  value = module.storage.storage_account_name
}

output "STORAGE_BLOB_ENDPOINT" {
  value = module.storage.blob_endpoint
}

output "STORAGE_DFS_ENDPOINT" {
  value = module.storage.dfs_endpoint
}

output "SEARCH_ENDPOINT" {
  value = local.search_endpoint
}

output "SEARCH_INDEX_NAME" {
  value = "documents"
}

output "SEARCH_NAME" {
  value = local.search_name
}

output "FOUNDRY_ACCOUNT_ENDPOINT" {
  value = local.foundry_account_endpoint
}

output "FOUNDRY_PROJECT_ENDPOINT" {
  value = local.foundry_project_endpoint
}

output "FOUNDRY_CHAT_DEPLOYMENT" {
  value = var.chat_deployment
}

output "FOUNDRY_EMBEDDING_DEPLOYMENT" {
  value = var.embedding_deployment
}

output "DOCUMENT_INTELLIGENCE_ENDPOINT" {
  value = module.document_intelligence.endpoint
}

output "SYNAPSE_SERVERLESS_SQL_ENDPOINT" {
  value = module.synapse.serverless_sql_endpoint
}

output "SYNAPSE_WORKSPACE_NAME" {
  value = module.synapse.workspace_name
}

output "APP_SERVICE_NAME" {
  value = module.appservice.site_name
}

output "APP_SERVICE_HOSTNAME" {
  value = module.appservice.default_host_name
}

# When DR is enabled the public URL is the Front Door endpoint (priority 1 = primary, 2 = secondary).
output "MCP_SERVER_BASE_URL" {
  value = local.enable_dr ? local.front_door_endpoint_url : "https://${module.appservice.default_host_name}"
}

output "MCP_PRIMARY_HOSTNAME" {
  value = module.appservice.default_host_name
}

output "MCP_SECONDARY_HOSTNAME" {
  value = local.enable_dr ? module.secondary[0].app_service_host_name : ""
}

output "FRONT_DOOR_ENDPOINT" {
  value = local.front_door_endpoint_url
}

output "FRONT_DOOR_ID" {
  value = local.front_door_id_header
}

output "FUNCTION_APP_NAME" {
  value = module.functions.function_app_name
}

# ---- Data Factory inventory (empty when ADF pipelines are disabled or factory is reused) ----
output "DATA_FACTORY_NAME" {
  value = local.data_factory_name
}

output "DATA_FACTORY_PIPELINE_NAMES" {
  value = var.use_existing_data_factory ? [] : module.datafactory[0].pipeline_names
}

output "DATA_FACTORY_LINKED_SERVICE_NAMES" {
  value = var.use_existing_data_factory ? [] : module.datafactory[0].linked_service_names
}

output "DATA_FACTORY_TRIGGER_NAMES" {
  value = var.use_existing_data_factory ? [] : module.datafactory[0].trigger_names
}

output "SHIR_NAME" {
  value = var.use_existing_data_factory ? "" : module.datafactory[0].self_hosted_integration_runtime_name
}

# ---- SHIR host VM (empty when not deployed) ----
output "SHIR_HOST_VM_NAME" {
  value = var.enable_shir_host_vm ? module.shirhost[0].vm_name : ""
}

output "SHIR_HOST_PRIVATE_IP" {
  value = var.enable_shir_host_vm ? module.shirhost[0].private_ip : ""
}

# ---- Secondary region (empty when DR disabled) ----
output "AZURE_SECONDARY_LOCATION" {
  value = local.enable_dr ? var.secondary_location : ""
}

output "AZURE_SECONDARY_RESOURCE_GROUP" {
  value = local.enable_dr ? azurerm_resource_group.dr[0].name : ""
}

output "STORAGE_ACCOUNT_NAME_DR" {
  value = local.enable_dr ? module.secondary[0].storage_account_name : ""
}

output "STORAGE_BLOB_ENDPOINT_DR" {
  value = local.enable_dr ? module.secondary[0].blob_endpoint : ""
}

output "SEARCH_ENDPOINT_DR" {
  value = local.enable_dr ? module.secondary[0].search_endpoint : ""
}

output "FOUNDRY_ACCOUNT_ENDPOINT_DR" {
  value = local.enable_dr ? module.secondary[0].foundry_account_endpoint : ""
}

output "DOCUMENT_INTELLIGENCE_ENDPOINT_DR" {
  value = local.enable_dr ? module.secondary[0].document_intelligence_endpoint : ""
}

output "ENABLE_CMK" {
  value = var.enable_cmk ? "true" : "false"
}

output "CMK_KEY_URI" {
  value = local.cmk_key_uri
}

output "MCP_SERVER_IDENTITY_CLIENT_ID" {
  value = module.identity.mcp_server_identity_client_id
}

output "INGESTION_IDENTITY_CLIENT_ID" {
  value = module.identity.ingestion_identity_client_id
}

output "FUNCTION_APP_NAME_DR" {
  value = local.enable_dr ? module.secondary[0].function_app_name : ""
}

output "APP_SERVICE_NAME_DR" {
  value = local.enable_dr ? module.secondary[0].app_service_name : ""
}

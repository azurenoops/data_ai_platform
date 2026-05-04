module "monitoring" {
  source = "./modules/monitoring"

  resource_group_name = azurerm_resource_group.primary.name
  location            = var.location
  tags                = local.tags
  log_analytics_name  = local.names.log_analytics
  app_insights_name   = local.names.app_insights
}

module "identity" {
  source = "./modules/identity"

  resource_group_name        = azurerm_resource_group.primary.name
  location                   = var.location
  tags                       = local.tags
  mcp_server_identity_name   = local.names.mcp_server_identity
  ingestion_identity_name    = local.names.ingestion_identity
  data_factory_identity_name = local.names.data_factory_identity
}

module "keyvault" {
  source = "./modules/keyvault"

  resource_group_name           = azurerm_resource_group.primary.name
  location                      = var.location
  tags                          = local.tags
  key_vault_name                = local.names.key_vault
  enable_purge_protection       = var.enable_cmk
  soft_delete_retention_in_days = var.enable_cmk ? 90 : 7
  tenant_id                     = data.azurerm_client_config.current.tenant_id
}

module "cmk" {
  source = "./modules/cmk"
  count  = var.enable_cmk ? 1 : 0

  resource_group_name = azurerm_resource_group.primary.name
  location            = var.location
  tags                = local.tags
  key_vault_id        = module.keyvault.key_vault_id
  key_vault_uri       = module.keyvault.key_vault_uri
  cmk_identity_name   = local.names.cmk_identity
}

locals {
  cmk_key_uri                             = var.enable_cmk ? module.cmk[0].key_uri : ""
  cmk_user_assigned_identity_id           = var.enable_cmk ? module.cmk[0].cmk_identity_id : ""
  cmk_user_assigned_identity_client_id    = var.enable_cmk ? module.cmk[0].cmk_identity_client_id : ""
  cmk_user_assigned_identity_principal_id = var.enable_cmk ? module.cmk[0].cmk_identity_principal_id : ""
  cmk_key_name                            = var.enable_cmk ? module.cmk[0].key_name : ""
  cmk_key_vault_uri                       = var.enable_cmk ? module.cmk[0].key_vault_uri : ""
}

module "storage" {
  source = "./modules/storage"

  resource_group_name           = azurerm_resource_group.primary.name
  location                      = var.location
  tags                          = local.tags
  storage_account_name          = local.names.storage_account
  sku_name                      = local.effective_storage_sku
  cmk_key_uri                   = local.cmk_key_uri
  cmk_user_assigned_identity_id = local.cmk_user_assigned_identity_id
  containers                    = ["landing", "raw", "curated", "chunks", "deploy"]
}

module "search" {
  source = "./modules/search"

  resource_group_name = azurerm_resource_group.primary.name
  location            = var.location
  tags                = local.tags
  search_name         = local.names.search
  sku                 = var.search_sku
  enforce_cmk         = var.enable_cmk
}

module "foundry" {
  source = "./modules/foundry"

  resource_group_name                  = azurerm_resource_group.primary.name
  location                             = var.location
  tags                                 = local.tags
  account_name                         = local.names.foundry_account
  project_name                         = local.names.foundry_project
  chat_deployment                      = var.chat_deployment
  chat_mini_deployment                 = var.chat_mini_deployment
  embedding_deployment                 = var.embedding_deployment
  search_account_id                    = module.search.search_id
  storage_account_id                   = module.storage.storage_id
  cmk_key_uri                          = local.cmk_key_uri
  cmk_user_assigned_identity_id        = local.cmk_user_assigned_identity_id
  cmk_user_assigned_identity_client_id = local.cmk_user_assigned_identity_client_id
}

module "document_intelligence" {
  source = "./modules/documentintelligence"

  resource_group_name                  = azurerm_resource_group.primary.name
  location                             = var.location
  tags                                 = local.tags
  account_name                         = local.names.document_intelligence
  cmk_key_uri                          = local.cmk_key_uri
  cmk_user_assigned_identity_id        = local.cmk_user_assigned_identity_id
  cmk_user_assigned_identity_client_id = local.cmk_user_assigned_identity_client_id
}

module "appservice" {
  source = "./modules/appservice"

  resource_group_name              = azurerm_resource_group.primary.name
  location                         = var.location
  tags                             = merge(local.tags, { "azd-service-name" = "mcp-server" })
  plan_name                        = local.names.app_service_plan
  site_name                        = local.names.app_service
  sku                              = var.app_service_plan_sku
  user_assigned_identity_id        = module.identity.mcp_server_identity_id
  user_assigned_identity_client_id = module.identity.mcp_server_identity_client_id
  app_insights_connection_string   = module.monitoring.app_insights_connection_string
  app_settings = {
    AZURE_CLIENT_ID                = module.identity.mcp_server_identity_client_id
    AZURE_TENANT_ID                = data.azurerm_client_config.current.tenant_id
    Search__Endpoint               = module.search.search_endpoint
    Search__IndexName              = "documents"
    Foundry__Endpoint              = module.foundry.account_endpoint
    Foundry__ProjectEndpoint       = module.foundry.project_endpoint
    Foundry__ChatDeployment        = var.chat_deployment
    Foundry__EmbeddingDeployment   = var.embedding_deployment
    Storage__AccountName           = module.storage.storage_account_name
    Storage__CuratedContainer      = "curated"
    Synapse__ServerlessSqlEndpoint = module.synapse.serverless_sql_endpoint
    Synapse__Database              = "master"
    Auth__TenantId                 = data.azurerm_client_config.current.tenant_id
    Auth__Audience                 = local.app_audience
    Search__CmkKeyVaultUri         = local.cmk_key_vault_uri
    Search__CmkKeyName             = local.cmk_key_name
  }
}

module "functions" {
  source = "./modules/functions"

  resource_group_name              = azurerm_resource_group.primary.name
  location                         = var.location
  tags                             = merge(local.tags, { "azd-service-name" = "ingestion-functions" })
  plan_name                        = local.names.function_plan
  function_app_name                = local.names.function_app
  storage_account_name             = module.storage.storage_account_name
  storage_dfs_endpoint             = module.storage.dfs_endpoint
  deployment_container_name        = "deploy"
  user_assigned_identity_id        = module.identity.ingestion_identity_id
  user_assigned_identity_client_id = module.identity.ingestion_identity_client_id
  app_insights_connection_string   = module.monitoring.app_insights_connection_string
  app_settings = {
    AZURE_CLIENT_ID                = module.identity.ingestion_identity_client_id
    Storage__AccountName           = module.storage.storage_account_name
    Storage__LandingContainer      = "landing"
    Storage__RawContainer          = "raw"
    Storage__CuratedContainer      = "curated"
    Storage__ChunksContainer       = "chunks"
    Search__Endpoint               = module.search.search_endpoint
    Search__IndexName              = "documents"
    Foundry__Endpoint              = module.foundry.account_endpoint
    Foundry__EmbeddingDeployment   = var.embedding_deployment
    DocumentIntelligence__Endpoint = module.document_intelligence.endpoint
    Graph__TenantId                = data.azurerm_client_config.current.tenant_id
    SharePoint__Schedule           = "0 */30 * * * *"
    OneDrive__Schedule             = "0 0 */6 * * *"
    Search__CmkKeyVaultUri         = local.cmk_key_vault_uri
    Search__CmkKeyName             = local.cmk_key_name
  }
}

module "datafactory" {
  source = "./modules/datafactory"

  resource_group_name       = azurerm_resource_group.primary.name
  location                  = var.location
  tags                      = local.tags
  factory_name              = local.names.data_factory
  user_assigned_identity_id = module.identity.data_factory_identity_id

  # Wired-from-root references (used when pipelines are enabled)
  key_vault_id                    = module.keyvault.key_vault_id
  key_vault_uri                   = module.keyvault.key_vault_uri
  key_vault_name                  = module.keyvault.key_vault_name
  storage_account_name            = module.storage.storage_account_name
  storage_dfs_endpoint            = module.storage.dfs_endpoint
  data_factory_identity_client_id = module.identity.data_factory_identity_client_id

  # Master switches
  enable_data_factory_pipelines = var.enable_data_factory_pipelines
  enable_data_factory_schedules = var.enable_data_factory_schedules

  # SQL MI
  sql_mi_server_fqdn   = var.sql_mi_server_fqdn
  sql_mi_database      = var.sql_mi_database
  sql_mi_tables        = var.sql_mi_tables
  sql_mi_schedule_cron = var.sql_mi_schedule_cron

  # AFS
  afs_storage_account_name    = var.afs_storage_account_name
  afs_share_name              = var.afs_share_name
  afs_storage_key_secret_name = var.afs_storage_key_secret_name
  afs_schedule_cron           = var.afs_schedule_cron

  # SharePoint Online lists
  sharepoint_site_url            = var.sharepoint_site_url
  sharepoint_lists               = var.sharepoint_lists
  sharepoint_aad_app_tenant_id   = var.sharepoint_aad_app_tenant_id
  sharepoint_aad_app_client_id   = var.sharepoint_aad_app_client_id
  sharepoint_aad_app_secret_name = var.sharepoint_aad_app_secret_name
  sharepoint_schedule_cron       = var.sharepoint_schedule_cron

  # Dataverse
  dataverse_synapselink_path = var.dataverse_synapselink_path
  dataverse_schedule_cron    = var.dataverse_schedule_cron
  dataverse_probe_enabled    = var.dataverse_probe_enabled

  # SHIR
  enable_self_hosted_integration_runtime = var.enable_self_hosted_integration_runtime
  self_hosted_integration_runtime_name   = var.self_hosted_integration_runtime_name
  sql_mi_use_shir                        = var.sql_mi_use_shir
  afs_use_shir                           = var.afs_use_shir
  sharepoint_use_shir                    = var.sharepoint_use_shir
}

module "synapse" {
  source = "./modules/synapse"

  resource_group_name           = azurerm_resource_group.primary.name
  location                      = var.location
  tags                          = local.tags
  workspace_name                = local.names.synapse_workspace
  storage_account_id            = module.storage.storage_id
  storage_filesystem_id         = module.storage.filesystem_ids["curated"]
  sql_admin_login               = "syn_admin"
  sql_admin_aad_object_id       = var.principal_id
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  cmk_key_uri                   = local.cmk_key_uri
  cmk_user_assigned_identity_id = local.cmk_user_assigned_identity_id
}

# ---------------------------------------------------------------------------
# Self-Hosted Integration Runtime host VM (opt-in).
#
# Requires enable_self_hosted_integration_runtime = true AND a non-null
# shir_host_subnet_id. The precondition lifecycle blocks below fail at plan
# time rather than at apply when those constraints are not met.
# ---------------------------------------------------------------------------

module "shirhost" {
  source = "./modules/shirhost"
  count  = var.enable_shir_host_vm ? 1 : 0

  resource_group_name = azurerm_resource_group.primary.name
  location            = var.location
  tags                = local.tags

  vm_name           = "vm-shir-${local.resource_token}"
  vm_size           = var.shir_host_vm_size
  vm_admin_username = var.shir_host_vm_admin_username

  subnet_id                     = var.shir_host_subnet_id
  bastion_subnet_address_prefix = var.shir_host_bastion_subnet_address_prefix

  key_vault_id         = module.keyvault.key_vault_id
  storage_account_name = module.storage.storage_account_name
  storage_account_id   = module.storage.storage_id

  shir_authorization_key = module.datafactory.self_hosted_integration_runtime_primary_key
  shir_installer_url     = var.shir_installer_url
  shir_install_method    = var.shir_install_method
  dsc_zip_path           = "${path.module}/modules/shirhost/dsc/InstallShir.zip"
}

# Plan-time guards for the SHIR host VM's prerequisites.
resource "null_resource" "shir_host_preconditions" {
  count = var.enable_shir_host_vm ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.enable_self_hosted_integration_runtime
      error_message = "enable_shir_host_vm requires enable_self_hosted_integration_runtime to also be true."
    }
    precondition {
      condition     = var.shir_host_subnet_id != null
      error_message = "enable_shir_host_vm requires shir_host_subnet_id to be set to an existing subnet ID."
    }
  }
}

# ---------------------------------------------------------------------------
# Alerting (opt-in). Lives at root level (not inside `monitoring`) so that
# alerts can reference both monitoring + functions + datafactory + foundry +
# shirhost outputs without creating a circular module dependency.
# ---------------------------------------------------------------------------

locals {
  # Operator-managed KV secrets monitored by the kv_secret_expiry alert.
  # Each entry is conditional on the source that depends on the secret.
  tracked_secrets = compact([
    var.enable_data_factory_pipelines && var.afs_storage_account_name != null ? var.afs_storage_key_secret_name : "",
    var.enable_data_factory_pipelines && var.sharepoint_site_url != null ? var.sharepoint_aad_app_secret_name : "",
    var.enable_shir_host_vm ? "shir-host-admin-password" : "",
  ])
}

module "alerts" {
  source = "./modules/alerts"

  resource_group_name = azurerm_resource_group.primary.name
  location            = var.location
  tags                = local.tags

  alert_email_recipients              = var.alert_email_recipients
  alert_webhook_url                   = var.alert_webhook_url
  kv_secret_expiry_threshold_days     = var.kv_secret_expiry_threshold_days
  function_failure_rate_threshold_pct = var.function_failure_rate_threshold_pct
  embedding_throttle_threshold_count  = var.embedding_throttle_threshold_count
  search_ingestion_latency_p95_ms     = var.search_ingestion_latency_p95_ms
  shir_host_cpu_threshold_pct         = var.shir_host_cpu_threshold_pct

  log_analytics_id = module.monitoring.log_analytics_id
  app_insights_id  = module.monitoring.app_insights_id

  key_vault_id    = module.keyvault.key_vault_id
  tracked_secrets = local.tracked_secrets

  function_app_id    = module.functions.function_app_id
  data_factory_id    = module.datafactory.factory_id
  foundry_account_id = module.foundry.account_id
  shir_host_vm_id    = var.enable_shir_host_vm ? module.shirhost[0].vm_id : null
}

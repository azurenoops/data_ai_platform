module "storage" {
  source = "../storage"

  resource_group_name           = var.resource_group_name
  location                      = var.location
  tags                          = var.tags
  storage_account_name          = substr(replace("${var.abbrs.storageAccounts}dr${var.resource_token}", "-", ""), 0, 24)
  sku_name                      = var.storage_sku
  cmk_key_uri                   = var.cmk_key_uri
  cmk_user_assigned_identity_id = var.cmk_user_assigned_identity_id
  containers                    = ["landing", "raw", "curated", "chunks", "deploy"]
}

module "search" {
  source = "../search"

  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
  search_name         = "${var.abbrs.search}-dr-${var.resource_token}"
  sku                 = var.search_sku
  enforce_cmk         = var.cmk_key_uri != ""
}

module "foundry" {
  source = "../foundry"

  resource_group_name                  = var.resource_group_name
  location                             = var.location
  tags                                 = var.tags
  account_name                         = "${var.abbrs.cognitiveServicesAccounts}-foundry-dr-${var.resource_token}"
  project_name                         = "proj-dr-${var.resource_token}"
  chat_deployment                      = var.chat_deployment
  chat_mini_deployment                 = var.chat_mini_deployment
  embedding_deployment                 = var.embedding_deployment
  search_account_id                    = module.search.search_id
  storage_account_id                   = module.storage.storage_id
  cmk_key_uri                          = var.cmk_key_uri
  cmk_user_assigned_identity_id        = var.cmk_user_assigned_identity_id
  cmk_user_assigned_identity_client_id = var.cmk_user_assigned_identity_client_id
}

module "document_intelligence" {
  source = "../documentintelligence"

  resource_group_name                  = var.resource_group_name
  location                             = var.location
  tags                                 = var.tags
  account_name                         = "${var.abbrs.cognitiveServicesAccounts}-di-dr-${var.resource_token}"
  cmk_key_uri                          = var.cmk_key_uri
  cmk_user_assigned_identity_id        = var.cmk_user_assigned_identity_id
  cmk_user_assigned_identity_client_id = var.cmk_user_assigned_identity_client_id
}

module "appservice" {
  source = "../appservice"

  resource_group_name              = var.resource_group_name
  location                         = var.location
  tags                             = merge(var.tags, { "azd-service-name" = "mcp-server" })
  plan_name                        = "${var.abbrs.appServicePlans}-dr-${var.resource_token}"
  site_name                        = "${var.abbrs.sites}-mcp-dr-${var.resource_token}"
  sku                              = var.app_service_plan_sku
  user_assigned_identity_id        = var.mcp_server_user_assigned_identity_id
  user_assigned_identity_client_id = var.mcp_server_user_assigned_identity_client_id
  app_insights_connection_string   = var.app_insights_connection_string
  public_network_access_enabled    = var.mcp_public_network_access_enabled
  app_settings = {
    AZURE_CLIENT_ID                              = var.mcp_server_user_assigned_identity_client_id
    AZURE_TENANT_ID                              = var.tenant_id
    Search__Endpoint                             = module.search.search_endpoint
    Search__IndexName                            = "documents"
    Search__SecondaryEndpoint                    = module.search.search_endpoint
    Foundry__Endpoint                            = module.foundry.account_endpoint
    Foundry__ProjectEndpoint                     = module.foundry.project_endpoint
    Foundry__ChatDeployment                      = var.chat_deployment
    Foundry__EmbeddingDeployment                 = var.embedding_deployment
    Storage__AccountName                         = module.storage.storage_account_name
    Storage__CuratedContainer                    = "curated"
    WEBSITE_RUN_FROM_PACKAGE                     = "${module.storage.blob_endpoint}deploy/mcp-server-current.zip"
    WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID = var.mcp_server_user_assigned_identity_id
    Synapse__ServerlessSqlEndpoint               = ""
    Synapse__Database                            = "master"
    Auth__TenantId                               = var.tenant_id
    Auth__Audience                               = var.app_audience
    Search__CmkKeyVaultUri                       = var.cmk_key_vault_uri
    Search__CmkKeyName                           = var.cmk_key_name
  }
}

module "functions" {
  source = "../functions"

  resource_group_name              = var.resource_group_name
  location                         = var.location
  tags                             = merge(var.tags, { "azd-service-name" = "ingestion-functions" })
  plan_name                        = "${var.abbrs.appServicePlans}-ep1-dr-${var.resource_token}"
  function_app_name                = "${var.abbrs.functionApps}-ing-dr-${var.resource_token}"
  storage_account_name             = module.storage.storage_account_name
  user_assigned_identity_id        = var.ingestion_user_assigned_identity_id
  user_assigned_identity_client_id = var.ingestion_user_assigned_identity_client_id
  app_insights_connection_string   = var.app_insights_connection_string
  app_settings = {
    AZURE_CLIENT_ID                = var.ingestion_user_assigned_identity_client_id
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
    Graph__TenantId                = var.tenant_id
    # Schedules disabled in DR region so we don't double-trigger SharePoint sync. Primary owns scheduled fetch.
    SharePoint__Schedule                         = "0 0 0 1 1 0"
    OneDrive__Schedule                           = "0 0 0 1 1 0"
    WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID = var.ingestion_user_assigned_identity_id
    Search__CmkKeyVaultUri                       = var.cmk_key_vault_uri
    Search__CmkKeyName                           = var.cmk_key_name
    PrimaryRegion__StorageAccountName            = var.primary_storage_account_name
  }
}

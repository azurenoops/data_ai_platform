module "monitoring" {
  source = "./modules/monitoring"

  resource_group_name = azurerm_resource_group.primary.name
  location            = var.location
  tags                = local.tags
  log_analytics_name  = local.names.log_analytics
  app_insights_name   = local.names.app_insights
}

# ---------------------------------------------------------------------------
# Networking
#
# Single regional VNet with three subnets:
#   snet-app        - App Service VNet integration (delegated to serverFarms)
#   snet-functions  - Function App VNet integration (delegated to serverFarms)
#   snet-pe         - Private endpoint NICs
#
# Plus private DNS zones for every service we PE (Search, Cognitive Services,
# and reserved zones for Storage/KV/Sites for follow-up phases). DNS zone
# names default to Azure US Government - override via var.private_dns_zone_names
# if retargeting to commercial Azure.
#
# In hub-and-spoke topologies the platform team usually owns the VNet and
# central private DNS. Set use_existing_vnet=true and supply the subnet IDs
# (existing_subnet_*_id) + a map of pre-existing private DNS zone IDs
# (existing_private_dns_zone_ids) to bypass this module entirely. The private
# endpoints still deploy; they simply land in the supplied PE subnet and link
# to the supplied private DNS zone IDs instead of the managed ones.
# ---------------------------------------------------------------------------
module "network" {
  source = "./modules/network"
  count  = var.use_existing_vnet ? 0 : 1

  resource_group_name             = azurerm_resource_group.primary.name
  location                        = var.location
  tags                            = local.tags
  vnet_name                       = local.names.vnet
  vnet_address_space              = var.vnet_address_space
  subnet_app_address_prefix       = var.subnet_app_address_prefix
  subnet_functions_address_prefix = var.subnet_functions_address_prefix
  subnet_pe_address_prefix        = var.subnet_pe_address_prefix
  private_dns_zone_names          = var.private_dns_zone_names
}

# Plan-time validator: when use_existing_vnet=true, every existing_* input
# must be supplied. terraform_data + lifecycle.precondition gives a clear
# error message instead of a downstream "value cannot be null" failure. The
# private endpoints depend on these values even when the VNet module is skipped.
resource "terraform_data" "validate_existing_vnet_inputs" {
  lifecycle {
    precondition {
      condition = !var.use_existing_vnet || (
        var.existing_subnet_app_id != null &&
        var.existing_subnet_functions_id != null &&
        var.existing_subnet_pe_id != null &&
        contains(keys(var.existing_private_dns_zone_ids), "search") &&
        contains(keys(var.existing_private_dns_zone_ids), "cognitiveservices")
      )
      error_message = "use_existing_vnet=true requires non-null existing_subnet_app_id, existing_subnet_functions_id, existing_subnet_pe_id, and existing_private_dns_zone_ids must contain at least the 'search' and 'cognitiveservices' keys."
    }
  }
}

# Indirection so downstream PEs and module wiring don't care whether the
# VNet/DNS were created here or supplied by a platform team. The PE resources
# consume these locals directly.
locals {
  subnet_app_id        = var.use_existing_vnet ? var.existing_subnet_app_id : module.network[0].subnet_app_id
  subnet_functions_id  = var.use_existing_vnet ? var.existing_subnet_functions_id : module.network[0].subnet_functions_id
  subnet_pe_id         = var.use_existing_vnet ? var.existing_subnet_pe_id : module.network[0].subnet_pe_id
  private_dns_zone_ids = var.use_existing_vnet ? var.existing_private_dns_zone_ids : module.network[0].private_dns_zone_ids
}

module "identity" {
  source = "./modules/identity"

  resource_group_name        = azurerm_resource_group.primary.name
  location                   = var.location
  tags                       = local.tags
  mcp_server_identity_name   = local.names.mcp_server_identity
  ingestion_identity_name    = local.names.ingestion_identity
  data_factory_identity_name = local.names.data_factory_identity
  portal_identity_name       = local.names.portal_identity
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
  count  = var.use_existing_search ? 0 : 1

  resource_group_name = azurerm_resource_group.primary.name
  location            = var.location
  tags                = local.tags
  search_name         = local.names.search
  sku                 = var.search_sku
  enforce_cmk         = var.enable_cmk
}

data "azurerm_search_service" "existing" {
  count               = var.use_existing_search ? 1 : 0
  name                = coalesce(var.existing_search_name, local.names.search)
  resource_group_name = coalesce(var.existing_search_resource_group_name, azurerm_resource_group.primary.name)
}

module "foundry" {
  source = "./modules/foundry"
  count  = var.use_existing_foundry_account ? 0 : 1

  resource_group_name                  = azurerm_resource_group.primary.name
  location                             = var.location
  tags                                 = local.tags
  account_name                         = local.names.foundry_account
  project_name                         = local.names.foundry_project
  chat_deployment                      = var.chat_deployment
  chat_mini_deployment                 = var.chat_mini_deployment
  embedding_deployment                 = var.embedding_deployment
  search_account_id                    = local.search_id
  storage_account_id                   = module.storage.storage_id
  cmk_key_uri                          = local.cmk_key_uri
  cmk_user_assigned_identity_id        = local.cmk_user_assigned_identity_id
  cmk_user_assigned_identity_client_id = local.cmk_user_assigned_identity_client_id
}

data "azurerm_cognitive_account" "existing_foundry" {
  count               = var.use_existing_foundry_account ? 1 : 0
  name                = coalesce(var.existing_foundry_account_name, local.names.foundry_account)
  resource_group_name = coalesce(var.existing_foundry_account_resource_group_name, azurerm_resource_group.primary.name)
}

# ---------------------------------------------------------------------------
# Indirection locals for resources that can be created OR referenced.
#
# Every downstream consumer (RBAC, app settings, alerts, outputs) reads from
# these locals instead of `module.X.*` directly, so the create-vs-reference
# decision is invisible to the rest of the composition.
# ---------------------------------------------------------------------------
locals {
  search_id           = var.use_existing_search ? data.azurerm_search_service.existing[0].id : module.search[0].search_id
  search_name         = var.use_existing_search ? data.azurerm_search_service.existing[0].name : module.search[0].search_name
  search_endpoint     = var.use_existing_search ? "https://${data.azurerm_search_service.existing[0].name}.search.windows.net" : module.search[0].search_endpoint
  search_principal_id = var.use_existing_search ? try(data.azurerm_search_service.existing[0].identity[0].principal_id, "") : module.search[0].search_principal_id

  foundry_account_id       = var.use_existing_foundry_account ? data.azurerm_cognitive_account.existing_foundry[0].id : module.foundry[0].account_id
  foundry_account_endpoint = var.use_existing_foundry_account ? data.azurerm_cognitive_account.existing_foundry[0].endpoint : module.foundry[0].account_endpoint
  foundry_project_name     = var.use_existing_foundry_account ? coalesce(var.existing_foundry_project_name, local.names.foundry_project) : module.foundry[0].project_name
  foundry_project_endpoint = var.use_existing_foundry_account ? "${data.azurerm_cognitive_account.existing_foundry[0].endpoint}api/projects/${local.foundry_project_name}" : module.foundry[0].project_endpoint
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

module "cosmosdb" {
  source = "./modules/cosmosdb"

  resource_group_name           = azurerm_resource_group.primary.name
  location                      = var.location
  tags                          = local.tags
  account_name                  = local.names.cosmos_account
  database_name                 = var.cosmos_db_database_name
  source_config_container_name  = var.cosmos_db_source_config_container_name
  public_network_access_enabled = var.cosmos_db_public_network_access_enabled
}

# ---------------------------------------------------------------------------
# Private endpoints
#
# AI Search, Document Intelligence, and Foundry all run with public network
# access disabled (Navy NIST 800-53 policy "Azure AI Services resources
# should restrict network access"). Bring them onto the VNet via private
# endpoints so the App Service + Function App (also VNet-integrated) can
# reach them.
#
# When use_existing_X = true the resource lives outside this composition
# and has its own networking - skip creating a PE in our VNet.
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "search" {
  count = var.use_existing_search ? 0 : 1

  name                = "pep-${local.names.search}"
  resource_group_name = azurerm_resource_group.primary.name
  location            = var.location
  subnet_id           = local.subnet_pe_id
  tags                = local.tags

  private_service_connection {
    name                           = "search"
    private_connection_resource_id = local.search_id
    is_manual_connection           = false
    subresource_names              = ["searchService"]
  }

  private_dns_zone_group {
    name                 = "search"
    private_dns_zone_ids = [local.private_dns_zone_ids["search"]]
  }
}

resource "azurerm_private_endpoint" "document_intelligence" {
  name                = "pep-${local.names.document_intelligence}"
  resource_group_name = azurerm_resource_group.primary.name
  location            = var.location
  subnet_id           = local.subnet_pe_id
  tags                = local.tags

  private_service_connection {
    name                           = "documentintelligence"
    private_connection_resource_id = module.document_intelligence.account_id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  private_dns_zone_group {
    name                 = "cognitiveservices"
    private_dns_zone_ids = [local.private_dns_zone_ids["cognitiveservices"]]
  }
}

resource "azurerm_private_endpoint" "foundry" {
  count = var.use_existing_foundry_account ? 0 : 1

  name                = "pep-${local.names.foundry_account}"
  resource_group_name = azurerm_resource_group.primary.name
  location            = var.location
  subnet_id           = local.subnet_pe_id
  tags                = local.tags

  private_service_connection {
    name                           = "foundry"
    private_connection_resource_id = local.foundry_account_id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  private_dns_zone_group {
    name                 = "cognitiveservices"
    private_dns_zone_ids = [local.private_dns_zone_ids["cognitiveservices"]]
  }
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
  virtual_network_subnet_id        = local.subnet_app_id
  public_network_access_enabled    = var.mcp_public_network_access_enabled
  app_settings = {
    AZURE_CLIENT_ID                              = module.identity.mcp_server_identity_client_id
    AZURE_TENANT_ID                              = data.azurerm_client_config.current.tenant_id
    Search__Endpoint                             = local.search_endpoint
    Search__IndexName                            = "documents"
    Foundry__Endpoint                            = local.foundry_account_endpoint
    Foundry__ProjectEndpoint                     = local.foundry_project_endpoint
    Foundry__ChatDeployment                      = var.chat_deployment
    Foundry__EmbeddingDeployment                 = var.embedding_deployment
    Storage__AccountName                         = module.storage.storage_account_name
    Storage__CuratedContainer                    = "curated"
    WEBSITE_RUN_FROM_PACKAGE                     = "${module.storage.blob_endpoint}deploy/mcp-server-current.zip"
    WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID = module.identity.mcp_server_identity_id
    Synapse__ServerlessSqlEndpoint               = module.synapse.serverless_sql_endpoint
    Synapse__Database                            = "master"
    Auth__TenantId                               = data.azurerm_client_config.current.tenant_id
    Auth__Audience                               = local.app_audience
    Search__CmkKeyVaultUri                       = local.cmk_key_vault_uri
    Search__CmkKeyName                           = local.cmk_key_name
  }
}

module "portal_appservice" {
  source = "./modules/appservice"

  resource_group_name              = azurerm_resource_group.primary.name
  location                         = var.location
  tags                             = merge(local.tags, { "azd-service-name" = "portal" })
  plan_name                        = "${local.names.app_service_plan}-portal"
  site_name                        = local.names.portal_app_service
  sku                              = var.app_service_plan_sku
  user_assigned_identity_id        = module.identity.portal_identity_id
  user_assigned_identity_client_id = module.identity.portal_identity_client_id
  app_insights_connection_string   = module.monitoring.app_insights_connection_string
  virtual_network_subnet_id        = local.subnet_app_id
  public_network_access_enabled    = var.portal_public_network_access_enabled
  app_settings = {
    AZURE_CLIENT_ID                              = module.identity.portal_identity_client_id
    Portal__McpBaseUrl                           = local.enable_dr ? local.front_door_endpoint_url : "https://${module.appservice.default_host_name}"
    Portal__McpAudience                          = local.app_audience
    Portal__SubscriptionId                       = data.azurerm_subscription.current.subscription_id
    Portal__ResourceGroupName                    = azurerm_resource_group.primary.name
    Portal__DataFactoryName                      = coalesce(var.existing_data_factory_name, local.names.data_factory)
    Portal__SqlPipelineName                      = "pl_sql_mi_to_adls"
    Portal__StorageAccountUrl                    = module.storage.blob_endpoint
    Portal__LandingContainerName                 = "landing"
    AzureAd__Instance                            = var.portal_azuread_instance
    AzureAd__TenantId                            = var.portal_azuread_tenant_id != "" ? var.portal_azuread_tenant_id : data.azurerm_client_config.current.tenant_id
    AzureAd__ClientId                            = var.portal_azuread_client_id
    AzureAd__CallbackPath                        = "/signin-oidc"
    AzureAd__SignedOutCallbackPath               = "/signout-callback-oidc"
    CosmosDb__Endpoint                           = module.cosmosdb.endpoint
    CosmosDb__DatabaseId                         = module.cosmosdb.database_name
    CosmosDb__SourceConfigContainerId            = module.cosmosdb.source_config_container_name
    WEBSITE_RUN_FROM_PACKAGE                     = "${module.storage.blob_endpoint}deploy/portal-current.zip"
    WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID = module.identity.portal_identity_id
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
  user_assigned_identity_id        = module.identity.ingestion_identity_id
  user_assigned_identity_client_id = module.identity.ingestion_identity_client_id
  app_insights_connection_string   = module.monitoring.app_insights_connection_string
  virtual_network_subnet_id        = local.subnet_functions_id
  app_settings = {
    AZURE_CLIENT_ID                              = module.identity.ingestion_identity_client_id
    Storage__AccountName                         = module.storage.storage_account_name
    Storage__LandingContainer                    = "landing"
    Storage__RawContainer                        = "raw"
    Storage__CuratedContainer                    = "curated"
    Storage__ChunksContainer                     = "chunks"
    Search__Endpoint                             = local.search_endpoint
    Search__IndexName                            = "documents"
    Foundry__Endpoint                            = local.foundry_account_endpoint
    Foundry__EmbeddingDeployment                 = var.embedding_deployment
    DocumentIntelligence__Endpoint               = module.document_intelligence.endpoint
    Graph__TenantId                              = data.azurerm_client_config.current.tenant_id
    CosmosDb__Endpoint                           = module.cosmosdb.endpoint
    CosmosDb__DatabaseId                         = module.cosmosdb.database_name
    CosmosDb__SourceConfigContainerId            = module.cosmosdb.source_config_container_name
    WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID = module.identity.ingestion_identity_id
    Search__CmkKeyVaultUri                       = local.cmk_key_vault_uri
    Search__CmkKeyName                           = local.cmk_key_name
  }
}

module "datafactory" {
  source = "./modules/datafactory"
  count  = var.use_existing_data_factory ? 0 : 1

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

data "azurerm_data_factory" "existing" {
  count               = var.use_existing_data_factory ? 1 : 0
  name                = coalesce(var.existing_data_factory_name, local.names.data_factory)
  resource_group_name = coalesce(var.existing_data_factory_resource_group_name, azurerm_resource_group.primary.name)
}

locals {
  data_factory_id   = var.use_existing_data_factory ? data.azurerm_data_factory.existing[0].id : module.datafactory[0].factory_id
  data_factory_name = var.use_existing_data_factory ? data.azurerm_data_factory.existing[0].name : module.datafactory[0].factory_name
}

module "synapse" {
  source = "./modules/synapse"

  resource_group_name           = azurerm_resource_group.primary.name
  location                      = var.location
  tags                          = local.tags
  workspace_name                = local.names.synapse_workspace
  storage_account_id            = module.storage.storage_id
  storage_filesystem_id         = module.storage.filesystem_ids["curated"]
  sql_admin_login               = "synadmin"
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

  shir_authorization_key = module.datafactory[0].self_hosted_integration_runtime_primary_key
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
    precondition {
      condition     = !var.use_existing_data_factory
      error_message = "enable_shir_host_vm is incompatible with use_existing_data_factory=true. The SHIR auth key is sourced from the Terraform-managed Data Factory's SHIR resource; bring your own SHIR registration when reusing an existing factory."
    }
  }
}

# ---------------------------------------------------------------------------
# Plan-time guards for the reuse-existing-resource toggles.
#
# Each precondition surfaces a contradiction (e.g. reusing the Data Factory
# while also asking Terraform to deploy pipelines onto it) before apply,
# rather than producing a confusing runtime error.
# ---------------------------------------------------------------------------
resource "null_resource" "reuse_existing_preconditions" {
  lifecycle {
    precondition {
      condition     = !(var.use_existing_data_factory && var.enable_data_factory_pipelines)
      error_message = "use_existing_data_factory=true is incompatible with enable_data_factory_pipelines=true. Pipeline / linked-service / trigger creation lives inside the datafactory module, which is skipped when the factory is reused. Manage pipelines on the referenced factory out-of-band."
    }
    precondition {
      condition     = !(var.use_existing_data_factory && var.enable_self_hosted_integration_runtime)
      error_message = "use_existing_data_factory=true is incompatible with enable_self_hosted_integration_runtime=true. SHIR provisioning lives inside the datafactory module; register the SHIR on the referenced factory out-of-band."
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
  data_factory_id    = local.data_factory_id
  foundry_account_id = local.foundry_account_id
  shir_host_vm_id    = var.enable_shir_host_vm ? module.shirhost[0].vm_id : null
}

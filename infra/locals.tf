locals {
  # Resource-name abbreviations - reused from the Bicep era unchanged.
  abbrs = jsondecode(file("${path.module}/abbreviations.json"))

  # Approximation of Bicep's `uniqueString(subscription().id, environmentName, location)` -
  # produces a 13-char lowercase hash that is deterministic for a (subscription, env, location) triple.
  # NOTE: this hash is *not* identical to what Bicep produces; resources will be named differently.
  resource_token = lower(substr(sha1("${data.azurerm_subscription.current.subscription_id}-${var.environment_name}-${var.location}"), 0, 13))

  enable_dr = var.secondary_location != ""

  # Storage SKU auto-promotes to RA-GZRS when DR is enabled (read failover).
  effective_storage_sku = local.enable_dr ? "Standard_RAGZRS" : var.storage_sku

  # Tags merged onto every resource. `azd-env-name` is preserved for back-compat with anything that
  # filters by it (Azure portal "Environments" view, cost grouping, etc.).
  tags = merge(
    {
      "azd-env-name" = var.environment_name
    },
    var.tags,
  )

  # Names derived from abbreviations + token. Centralised so both primary and DR composition can reuse.
  names = {
    log_analytics         = "${local.abbrs.logAnalyticsWorkspaces}-${local.resource_token}"
    app_insights          = "${local.abbrs.applicationInsights}-${local.resource_token}"
    mcp_server_identity   = "${local.abbrs.managedIdentityUserAssignedIdentities}-mcp-${local.resource_token}"
    ingestion_identity    = "${local.abbrs.managedIdentityUserAssignedIdentities}-ing-${local.resource_token}"
    data_factory_identity = "${local.abbrs.managedIdentityUserAssignedIdentities}-adf-${local.resource_token}"
    cmk_identity          = "${local.abbrs.managedIdentityUserAssignedIdentities}-cmk-${local.resource_token}"
    key_vault             = substr("${local.abbrs.keyVaults}-${local.resource_token}", 0, 24)
    storage_account       = substr(replace("${local.abbrs.storageAccounts}${local.resource_token}", "-", ""), 0, 24)
    search                = "${local.abbrs.search}-${local.resource_token}"
    foundry_account       = "${local.abbrs.cognitiveServicesAccounts}-foundry-${local.resource_token}"
    foundry_project       = "proj-${local.resource_token}"
    document_intelligence = "${local.abbrs.cognitiveServicesAccounts}-di-${local.resource_token}"
    app_service_plan      = "${local.abbrs.appServicePlans}-${local.resource_token}"
    app_service           = "${local.abbrs.sites}-mcp-${local.resource_token}"
    function_plan         = "${local.abbrs.appServicePlans}-flex-${local.resource_token}"
    function_app          = "${local.abbrs.functionApps}-ing-${local.resource_token}"
    data_factory          = "${local.abbrs.dataFactories}-${local.resource_token}"
    synapse_workspace     = "${local.abbrs.synapseWorkspaces}-${local.resource_token}"
    front_door            = "fd-${local.resource_token}"
  }

  app_audience = "api://${local.abbrs.sites}-mcp-${local.resource_token}"
}

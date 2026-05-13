locals {
  # AzureWebJobsStorage settings that pin the Functions host's storage auth
  # to the user-assigned managed identity. Shared key is disabled on the
  # platform's storage account, so connection-string auth is not an option.
  # See: https://learn.microsoft.com/azure/azure-functions/functions-reference#configure-an-identity-based-connection
  base_app_settings = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.app_insights_connection_string
    AzureWebJobsStorage__accountName      = var.storage_account_name
    AzureWebJobsStorage__credential       = "managedidentity"
    AzureWebJobsStorage__clientId         = var.user_assigned_identity_client_id
  }

  merged_app_settings = merge(local.base_app_settings, var.app_settings)
}

# Elastic Premium (EP1) — drop-in replacement for FlexConsumption (FC1) on
# Gov tenants where Microsoft.Web/FlexConsumption is not enabled on the
# subscription. EP1 supports:
#   - VNet integration (required since AI Search + Document Intelligence
#     run with publicNetworkAccess = "disabled")
#   - User-assigned managed identity for storage auth
#   - Always-warm workers (no cold starts)
#   - 60-min execution timeout
# Cost note: EP1 is always-allocated (~$165/mo idle, commercial pricing,
# Gov typically +5-15%) versus FC1's pay-per-execution model. If FC1
# becomes available on the subscription, swap sku_name back and restore
# the azapi_resource + functionAppConfig block from git history.
resource "azurerm_service_plan" "this" {
  name                = var.plan_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  os_type  = "Linux"
  sku_name = "EP1"
}

resource "azurerm_linux_function_app" "this" {
  name                = var.function_app_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  service_plan_id = azurerm_service_plan.this.id

  virtual_network_subnet_id = var.virtual_network_subnet_id

  storage_account_name          = var.storage_account_name
  storage_uses_managed_identity = true

  https_only                      = true
  key_vault_reference_identity_id = var.user_assigned_identity_id

  identity {
    type         = "UserAssigned"
    identity_ids = [var.user_assigned_identity_id]
  }

  site_config {
    ftps_state          = "Disabled"
    minimum_tls_version = "1.2"
    http2_enabled       = true

    application_stack {
      dotnet_version              = "9.0"
      use_dotnet_isolated_runtime = true
    }
  }

  app_settings = local.merged_app_settings

  lifecycle {
    # The Functions deploy step in CI (`az functionapp deployment source
    # config-zip`) updates WEBSITE_RUN_FROM_PACKAGE on every deploy.
    # Ignoring it here prevents Terraform from fighting CI on subsequent
    # plans.
    ignore_changes = [
      app_settings["WEBSITE_RUN_FROM_PACKAGE"],
    ]
  }
}

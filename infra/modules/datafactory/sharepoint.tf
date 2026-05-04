# ---------------------------------------------------------------------------
# SharePoint Online lists ingestion (pl_sharepoint_lists_to_adls).
#
# Gated by enable_data_factory_pipelines AND non-null sharepoint_site_url /
# sharepoint_aad_app_client_id. The AAD app-registration client secret is
# stored in Key Vault by the operator (var.sharepoint_aad_app_secret_name).
# Files in SharePoint document libraries are NOT ingested here -- those go
# through the Functions Graph fetcher (SharePointFilesFunction).
# ---------------------------------------------------------------------------

locals {
  sharepoint_pipeline_props = jsondecode(file("${path.module}/../../datafactory/pipelines/pl_sharepoint_lists_to_adls.json")).properties
}

resource "azurerm_data_factory_linked_custom_service" "sharepoint" {
  count = local.enable_sharepoint ? 1 : 0

  name            = "ls_sharepoint"
  data_factory_id = azurerm_data_factory.this.id
  type            = "SharePointOnlineList"
  description     = "Source SharePoint Online site for list (NOT file) ingestion. App-reg secret referenced from Key Vault (${var.sharepoint_aad_app_secret_name})."

  integration_runtime {
    name = (local.enable_shir && var.sharepoint_use_shir) ? local.shir_name : "AutoResolveIntegrationRuntime"
  }

  type_properties_json = jsonencode({
    siteUrl                        = var.sharepoint_site_url
    tenantId                       = var.sharepoint_aad_app_tenant_id
    servicePrincipalId             = var.sharepoint_aad_app_client_id
    servicePrincipalCredentialType = "ServicePrincipalKey"
    servicePrincipalKey = {
      type       = "AzureKeyVaultSecret"
      store      = { referenceName = "ls_kv", type = "LinkedServiceReference" }
      secretName = var.sharepoint_aad_app_secret_name
    }
  })

  depends_on = [azurerm_data_factory_linked_custom_service.kv]
}

resource "azurerm_data_factory_custom_dataset" "sharepoint_list" {
  count = local.enable_sharepoint ? 1 : 0

  name            = "ds_sharepoint_list"
  data_factory_id = azurerm_data_factory.this.id
  type            = "SharePointOnlineListResource"

  linked_service {
    name = azurerm_data_factory_linked_custom_service.sharepoint[0].name
  }

  parameters = {
    siteUrl   = "default"
    listTitle = "default"
  }

  type_properties_json = jsonencode({
    listName = "@dataset().listTitle"
  })
}

resource "azapi_resource" "sharepoint_pipeline" {
  count = local.enable_sharepoint ? 1 : 0

  type      = "Microsoft.DataFactory/factories/pipelines@2018-06-01"
  parent_id = azurerm_data_factory.this.id
  name      = "pl_sharepoint_lists_to_adls"

  body = {
    properties = merge(local.sharepoint_pipeline_props, {
      parameters = merge(
        try(local.sharepoint_pipeline_props.parameters, {}),
        {
          siteUrl = {
            type         = "string"
            defaultValue = var.sharepoint_site_url
          }
          lists = {
            type         = "array"
            defaultValue = length(var.sharepoint_lists) > 0 ? [for l in var.sharepoint_lists : { name = l }] : local.sharepoint_pipeline_props.parameters.lists.defaultValue
          }
        }
      )
    })
  }

  depends_on = [
    azurerm_data_factory_custom_dataset.sharepoint_list,
    azurerm_data_factory_custom_dataset.adls_parquet,
  ]
}

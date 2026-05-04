data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

locals {
  base_app_settings = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.app_insights_connection_string
    AzureWebJobsStorage__accountName      = var.storage_account_name
    AzureWebJobsStorage__credential       = "managedidentity"
    AzureWebJobsStorage__clientId         = var.user_assigned_identity_client_id
  }

  merged_app_settings = merge(local.base_app_settings, var.app_settings)

  # Translate the dfs endpoint (https://acct.dfs.core.windows.net/) into the matching blob endpoint
  # (https://acct.blob.core.windows.net/) - the FlexConsumption deployment storage URL must point
  # at the blob endpoint, not dfs, even on HNS-enabled accounts.
  blob_root = replace(var.storage_dfs_endpoint, ".dfs.", ".blob.")

  app_settings_array = [for k, v in local.merged_app_settings : { name = k, value = v }]
}

resource "azurerm_service_plan" "this" {
  name                = var.plan_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  os_type  = "Linux"
  sku_name = "FC1"
}

# FlexConsumption + managed-identity-based deployment storage isn't fully exposed by the azurerm
# `azurerm_linux_function_app` resource yet. Use azapi to mirror the Bicep functionAppConfig block.
resource "azapi_resource" "function_app" {
  type      = "Microsoft.Web/sites@2024-04-01"
  name      = var.function_app_name
  parent_id = data.azurerm_resource_group.this.id
  location  = var.location
  tags      = var.tags

  body = {
    kind = "functionapp,linux"
    identity = {
      type = "UserAssigned"
      userAssignedIdentities = {
        (var.user_assigned_identity_id) = {}
      }
    }
    properties = {
      serverFarmId              = azurerm_service_plan.this.id
      httpsOnly                 = true
      keyVaultReferenceIdentity = var.user_assigned_identity_id
      functionAppConfig = {
        deployment = {
          storage = {
            type  = "blobContainer"
            value = "${local.blob_root}${var.deployment_container_name}"
            authentication = {
              type                           = "UserAssignedIdentity"
              userAssignedIdentityResourceId = var.user_assigned_identity_id
            }
          }
        }
        runtime = {
          name    = "dotnet-isolated"
          version = "9.0"
        }
        scaleAndConcurrency = {
          instanceMemoryMB     = 2048
          maximumInstanceCount = 100
        }
      }
      siteConfig = {
        ftpsState     = "Disabled"
        minTlsVersion = "1.2"
        http20Enabled = true
        appSettings   = local.app_settings_array
      }
    }
  }

  response_export_values = ["properties.defaultHostName"]
}

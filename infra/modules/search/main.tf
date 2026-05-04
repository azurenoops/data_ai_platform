data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

# AzAPI lets us pin the preview API version (2024-06-01-preview) and set encryptionWithCmk.enforcement
# the same way the Bicep did - the azurerm_search_service resource doesn't expose `enforcement` cleanly.
resource "azapi_resource" "search" {
  type      = "Microsoft.Search/searchServices@2024-06-01-preview"
  name      = var.search_name
  parent_id = data.azurerm_resource_group.this.id
  location  = var.location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    sku = {
      name = var.sku
    }
    properties = {
      replicaCount        = 1
      partitionCount      = 1
      hostingMode         = "default"
      publicNetworkAccess = "enabled"
      semanticSearch      = "standard"
      disableLocalAuth    = true
      authOptions         = null
      encryptionWithCmk = {
        enforcement = var.enforce_cmk ? "Enabled" : "Unspecified"
      }
    }
  }

  response_export_values = ["identity.principalId"]
}

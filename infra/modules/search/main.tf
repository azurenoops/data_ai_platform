# The resource group is created in the root composition (azurerm_resource_group.primary)
# in the same apply. Looking it up with `data "azurerm_resource_group" "this"` would race
# the RG creation and fail on the first apply ("Resource Group ... was not found"). The
# RG resource ID format is stable, so we derive it from the current subscription scope
# instead of a data lookup.
data "azurerm_subscription" "current" {}

locals {
  resource_group_id = "${data.azurerm_subscription.current.id}/resourceGroups/${var.resource_group_name}"
}

# AzAPI lets us pin the preview API version (2024-06-01-preview) and set encryptionWithCmk.enforcement
# the same way the Bicep did - the azurerm_search_service resource doesn't expose `enforcement` cleanly.
resource "azapi_resource" "search" {
  type      = "Microsoft.Search/searchServices@2024-06-01-preview"
  name      = var.search_name
  parent_id = local.resource_group_id
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
      replicaCount   = 1
      partitionCount = 1
      hostingMode    = "default"
      # Navy NIST 800-53 Custom Policy "Azure AI Services resources should
      # restrict network access" denies search services where
      # publicNetworkAccess is not "Disabled" AND no ipRules are configured.
      # Disable public access entirely; runtime callers reach the index via
      # the Private Endpoint defined in primary.tf.
      #
      # Case matters: Microsoft.Search canonicalises this field as
      # "Enabled" / "Disabled" (PascalCase). Lowercase values are silently
      # dropped and the property falls back to the API default ("Enabled"),
      # which then fails the policy check.
      publicNetworkAccess = "Disabled"
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

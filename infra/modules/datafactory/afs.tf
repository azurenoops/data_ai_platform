# ---------------------------------------------------------------------------
# Azure File Share ingestion (pl_afs_to_adls).
#
# Gated by enable_data_factory_pipelines AND non-null afs_storage_account_name
# / afs_share_name. The AFS storage account key cannot be obtained via managed
# identity, so it is stored in Key Vault by the operator
# (var.afs_storage_key_secret_name) and referenced via the AzureKeyVault
# linked service (ls_kv) in main.tf.
# ---------------------------------------------------------------------------

locals {
  afs_pipeline_props = jsondecode(file("${path.module}/../../datafactory/pipelines/pl_afs_to_adls.json")).properties
}

resource "azurerm_data_factory_linked_custom_service" "afs" {
  count = local.enable_afs ? 1 : 0

  name            = "ls_afs"
  data_factory_id = azurerm_data_factory.this.id
  type            = "AzureFileStorage"
  description     = "Source Azure File Share. Storage-account key referenced from Key Vault (${var.afs_storage_key_secret_name})."

  integration_runtime {
    name = (local.enable_shir && var.afs_use_shir) ? local.shir_name : "AutoResolveIntegrationRuntime"
  }

  type_properties_json = jsonencode({
    connectionString = "DefaultEndpointsProtocol=https;EndpointSuffix=core.windows.net;AccountName=${var.afs_storage_account_name};"
    fileShare        = var.afs_share_name
    accountKey = {
      type       = "AzureKeyVaultSecret"
      store      = { referenceName = "ls_kv", type = "LinkedServiceReference" }
      secretName = var.afs_storage_key_secret_name
    }
  })

  depends_on = [azurerm_data_factory_linked_custom_service.kv]
}

resource "azurerm_data_factory_custom_dataset" "afs_source" {
  count = local.enable_afs ? 1 : 0

  name            = "ds_afs_source"
  data_factory_id = azurerm_data_factory.this.id
  type            = "Binary"

  linked_service {
    name = azurerm_data_factory_linked_custom_service.afs[0].name
  }

  type_properties_json = jsonencode({
    location = {
      type       = "AzureFileStorageLocation"
      folderPath = "/"
    }
  })
}

resource "azurerm_data_factory_custom_dataset" "afs_inventory" {
  count = local.enable_afs ? 1 : 0

  name            = "ds_afs_inventory"
  data_factory_id = azurerm_data_factory.this.id
  type            = "DelimitedText"

  linked_service {
    name = azurerm_data_factory_linked_custom_service.afs[0].name
  }

  type_properties_json = jsonencode({
    location = {
      type       = "AzureFileStorageLocation"
      folderPath = "/_inventory"
    }
    columnDelimiter  = ","
    firstRowAsHeader = true
  })
}

resource "azapi_resource" "afs_pipeline" {
  count = local.enable_afs ? 1 : 0

  type      = "Microsoft.DataFactory/factories/pipelines@2018-06-01"
  parent_id = azurerm_data_factory.this.id
  name      = "pl_afs_to_adls"

  body = {
    properties = local.afs_pipeline_props
  }

  depends_on = [
    azurerm_data_factory_custom_dataset.afs_source,
    azurerm_data_factory_custom_dataset.afs_inventory,
    azurerm_data_factory_custom_dataset.adls_binary,
    azurerm_data_factory_custom_dataset.adls_parquet,
  ]
}

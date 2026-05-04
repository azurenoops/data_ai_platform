resource "azurerm_data_factory" "this" {
  name                = var.factory_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  public_network_enabled = true

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [var.user_assigned_identity_id]
  }
}

# ---------------------------------------------------------------------------
# Source enable flags + KV linked-service requirement.
#
# Each per-source file (sqlmi.tf, afs.tf, sharepoint.tf, dataverse.tf) is
# gated by both the master `enable_data_factory_pipelines` flag and the
# presence of its required connection variables (server FQDN, account name,
# site URL, etc.). Locals here centralise the truthiness so per-source
# `count` expressions stay one-liners.
# ---------------------------------------------------------------------------

locals {
  enable_pipelines  = var.enable_data_factory_pipelines
  enable_schedules  = var.enable_data_factory_pipelines && var.enable_data_factory_schedules
  enable_shir       = var.enable_self_hosted_integration_runtime
  enable_sqlmi      = local.enable_pipelines && var.sql_mi_server_fqdn != null && var.sql_mi_database != null
  enable_afs        = local.enable_pipelines && var.afs_storage_account_name != null && var.afs_share_name != null
  enable_sharepoint = local.enable_pipelines && var.sharepoint_site_url != null && var.sharepoint_aad_app_client_id != null
  enable_dataverse  = local.enable_pipelines
  # KV linked service required when any source needs to read a KV secret.
  enable_kv_ls = local.enable_pipelines && (local.enable_afs || local.enable_sharepoint)
  # Convenience reference to the SHIR name when wired through to a linked service.
  shir_name = local.enable_shir ? azurerm_data_factory_integration_runtime_self_hosted.this[0].name : null
}

# ---------------------------------------------------------------------------
# Always-on (when pipelines enabled): ADLS sink linked service + datasets.
# Managed-identity auth via the Data Factory's UAMI; reads `Storage Blob Data
# Contributor` granted in `infra/modules/roleassignments/main.tf`.
# ---------------------------------------------------------------------------

resource "azurerm_data_factory_linked_custom_service" "adls" {
  count = local.enable_pipelines ? 1 : 0

  name            = "ls_adls"
  data_factory_id = azurerm_data_factory.this.id
  type            = "AzureBlobFS"
  description     = "ADLS Gen2 sink. MI auth via the Data Factory's user-assigned identity."

  type_properties_json = jsonencode({
    url = var.storage_dfs_endpoint
  })
}

resource "azurerm_data_factory_custom_dataset" "adls_parquet" {
  count = local.enable_pipelines ? 1 : 0

  name            = "ds_adls_parquet"
  data_factory_id = azurerm_data_factory.this.id
  type            = "Parquet"

  linked_service {
    name = azurerm_data_factory_linked_custom_service.adls[0].name
  }

  parameters = {
    container = "raw"
    folder    = "default"
  }

  type_properties_json = jsonencode({
    location = {
      type       = "AzureBlobFSLocation"
      fileSystem = "@dataset().container"
      folderPath = "@dataset().folder"
    }
    compressionCodec = "snappy"
  })
}

resource "azurerm_data_factory_custom_dataset" "adls_binary" {
  count = local.enable_pipelines ? 1 : 0

  name            = "ds_adls_binary"
  data_factory_id = azurerm_data_factory.this.id
  type            = "Binary"

  linked_service {
    name = azurerm_data_factory_linked_custom_service.adls[0].name
  }

  parameters = {
    container = "landing"
    folder    = "default"
  }

  type_properties_json = jsonencode({
    location = {
      type       = "AzureBlobFSLocation"
      fileSystem = "@dataset().container"
      folderPath = "@dataset().folder"
    }
  })
}

# ---------------------------------------------------------------------------
# Key Vault linked service (deployed when any source needs KV-stored secrets).
# Uses the Data Factory's user-assigned identity (Key Vault Secrets User role
# granted in `infra/modules/roleassignments/main.tf`).
# ---------------------------------------------------------------------------

resource "azurerm_data_factory_linked_custom_service" "kv" {
  count = local.enable_kv_ls ? 1 : 0

  name            = "ls_kv"
  data_factory_id = azurerm_data_factory.this.id
  type            = "AzureKeyVault"
  description     = "Key Vault for operator-managed connector secrets. MI auth via the Data Factory's user-assigned identity."

  type_properties_json = jsonencode({
    baseUrl = var.key_vault_uri
  })
}

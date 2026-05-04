locals {
  cmk_enabled = var.cmk_key_uri != "" && var.cmk_user_assigned_identity_id != ""
}

resource "azurerm_storage_account" "this" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  account_tier             = element(split("_", var.sku_name), 0)
  account_replication_type = element(split("_", var.sku_name), 1)
  account_kind             = "StorageV2"

  is_hns_enabled                    = true
  shared_access_key_enabled         = false
  allow_nested_items_to_be_public   = false
  default_to_oauth_authentication   = true
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  public_network_access_enabled     = true
  infrastructure_encryption_enabled = local.cmk_enabled

  network_rules {
    bypass         = ["AzureServices"]
    default_action = "Allow"
  }

  dynamic "identity" {
    for_each = local.cmk_enabled ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [var.cmk_user_assigned_identity_id]
    }
  }

  dynamic "customer_managed_key" {
    for_each = local.cmk_enabled ? [1] : []
    content {
      key_vault_key_id          = var.cmk_key_uri
      user_assigned_identity_id = var.cmk_user_assigned_identity_id
    }
  }

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
}

# Use ADLS Gen2 filesystems instead of blob containers because the account has HNS enabled
# AND shared key access disabled (azurerm_storage_container can't authenticate without one of
# them, but the data_lake_gen2_filesystem resource talks to ARM directly).
resource "azurerm_storage_data_lake_gen2_filesystem" "containers" {
  for_each           = toset(var.containers)
  name               = each.value
  storage_account_id = azurerm_storage_account.this.id
}

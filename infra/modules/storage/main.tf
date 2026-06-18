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

  # CRITICAL: This account backs App Service WEBSITE_RUN_FROM_PACKAGE (Portal + MCP).
  # If publicNetworkAccess is disabled or defaultAction is Deny, App Service fails to mount
  # the package ZIP during startup (BadRunFromPackageConfig, 403 during volume mount).
  # The safe posture is: publicNetworkAccess=Enabled, defaultAction=Allow, bypass=AzureServices.
  # DO NOT change these settings without redesigning package delivery (e.g., via private
  # endpoints, ExpressRoute, or different storage path). See docs/DEPLOYMENT.md and repo memory.
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

  # Prevent accidental drift of network settings away from package-mount-safe posture.
  # Terraform will always enforce the above network_rules and public_network_access_enabled.
  # If Azure shows different values, 'terraform plan' will report the diff and 'terraform apply'
  # will correct it. This ensures the storage account stays accessible for WEBSITE_RUN_FROM_PACKAGE.
  lifecycle {
    ignore_changes = [
      # Azure may modify these after creation; we accept those changes but enforce network_rules
      # and public_network_access_enabled at all times (see policy above).
      customer_managed_key,  # Azure may finalize or adjust encryption metadata
    ]
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

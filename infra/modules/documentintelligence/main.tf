locals {
  cmk_enabled  = var.cmk_key_uri != "" && var.cmk_user_assigned_identity_id != ""
  cmk_key_name = local.cmk_enabled ? element(split("/", var.cmk_key_uri), length(split("/", var.cmk_key_uri)) - 1) : ""
  # Strip "/keys/<keyname>" off the versionless key URL to recover the vault URI (with trailing slash).
  cmk_vault_uri = local.cmk_enabled ? "${trimsuffix(var.cmk_key_uri, "/keys/${local.cmk_key_name}")}/" : ""
}

resource "azurerm_cognitive_account" "this" {
  name                = var.account_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  kind     = "FormRecognizer"
  sku_name = "S0"

  custom_subdomain_name         = var.account_name
  public_network_access_enabled = true
  local_auth_enabled            = false

  identity {
    type         = local.cmk_enabled ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = local.cmk_enabled ? [var.cmk_user_assigned_identity_id] : []
  }

  dynamic "customer_managed_key" {
    for_each = local.cmk_enabled ? [1] : []
    content {
      key_vault_key_id   = var.cmk_key_uri
      identity_client_id = var.cmk_user_assigned_identity_client_id
    }
  }
}

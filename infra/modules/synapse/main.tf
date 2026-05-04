data "azurerm_storage_account" "datalake" {
  name                = element(split("/", var.storage_account_id), length(split("/", var.storage_account_id)) - 1)
  resource_group_name = element(split("/", var.storage_account_id), 4)
}

# Bicep used `newGuid()` so the password rotated on every redeploy. random_password with stable
# `keepers` makes the password deterministic per workspace_name - documented behaviour change.
resource "random_password" "sql_admin" {
  length      = 32
  special     = true
  min_lower   = 4
  min_upper   = 4
  min_numeric = 4
  min_special = 2

  keepers = {
    workspace = var.workspace_name
  }
}

locals {
  cmk_enabled   = var.cmk_key_uri != "" && var.cmk_user_assigned_identity_id != ""
  cmk_key_name  = local.cmk_enabled ? element(split("/", var.cmk_key_uri), length(split("/", var.cmk_key_uri)) - 1) : ""
  cmk_vault_uri = local.cmk_enabled ? "${trimsuffix(var.cmk_key_uri, "/keys/${local.cmk_key_name}")}/" : ""
}

resource "azurerm_synapse_workspace" "this" {
  name                = var.workspace_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  storage_data_lake_gen2_filesystem_id = var.storage_filesystem_id

  sql_administrator_login          = var.sql_admin_login
  sql_administrator_login_password = random_password.sql_admin.result

  public_network_access_enabled = true
  azuread_authentication_only   = false

  identity {
    type         = local.cmk_enabled ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = local.cmk_enabled ? [var.cmk_user_assigned_identity_id] : []
  }

  dynamic "customer_managed_key" {
    for_each = local.cmk_enabled ? [1] : []
    content {
      key_versionless_id        = var.cmk_key_uri
      key_name                  = local.cmk_key_name
      user_assigned_identity_id = var.cmk_user_assigned_identity_id
    }
  }
}

resource "azurerm_synapse_firewall_rule" "allow_azure" {
  name                 = "AllowAllAzureServices"
  synapse_workspace_id = azurerm_synapse_workspace.this.id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "0.0.0.0"
}

resource "azurerm_synapse_workspace_aad_admin" "aad" {
  count = var.sql_admin_aad_object_id == "" ? 0 : 1

  synapse_workspace_id = azurerm_synapse_workspace.this.id
  login                = "aad-admin"
  object_id            = var.sql_admin_aad_object_id
  tenant_id            = var.tenant_id
}

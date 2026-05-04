resource "azurerm_user_assigned_identity" "cmk" {
  name                = var.cmk_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# "Key Vault Crypto Service Encryption User" - lets the UAMI wrap/unwrap with the key.
# Granted on the vault scope so the role survives key rotation.
resource "azurerm_role_assignment" "cmk_identity_kv_access" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.cmk.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_key_vault_key" "cmk" {
  name         = var.key_name
  key_vault_id = var.key_vault_id
  key_type     = "RSA"
  key_size     = 4096
  key_opts = [
    "wrapKey",
    "unwrapKey",
    "encrypt",
    "decrypt",
  ]

  rotation_policy {
    automatic {
      time_after_creation = "P11M"
    }
    expire_after         = "P2Y"
    notify_before_expiry = "P30D"
  }

  # Make sure the role assignment exists before we try to read versions for the consumers.
  depends_on = [azurerm_role_assignment.cmk_identity_kv_access]
}

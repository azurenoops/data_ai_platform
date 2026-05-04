output "key_id" {
  description = "Versioned key URL."
  value       = azurerm_key_vault_key.cmk.id
}

output "key_uri" {
  description = "Versionless key URL - resources rotate automatically when KV rotates."
  value       = azurerm_key_vault_key.cmk.versionless_id
}

output "key_name" {
  value = azurerm_key_vault_key.cmk.name
}

output "key_vault_uri" {
  value = var.key_vault_uri
}

output "cmk_identity_id" {
  value = azurerm_user_assigned_identity.cmk.id
}

output "cmk_identity_client_id" {
  value = azurerm_user_assigned_identity.cmk.client_id
}

output "cmk_identity_principal_id" {
  value = azurerm_user_assigned_identity.cmk.principal_id
}

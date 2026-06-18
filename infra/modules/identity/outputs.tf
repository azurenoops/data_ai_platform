output "mcp_server_identity_id" {
  value = azurerm_user_assigned_identity.mcp_server.id
}

output "mcp_server_identity_client_id" {
  value = azurerm_user_assigned_identity.mcp_server.client_id
}

output "mcp_server_principal_id" {
  value = azurerm_user_assigned_identity.mcp_server.principal_id
}

output "ingestion_identity_id" {
  value = azurerm_user_assigned_identity.ingestion.id
}

output "ingestion_identity_client_id" {
  value = azurerm_user_assigned_identity.ingestion.client_id
}

output "ingestion_principal_id" {
  value = azurerm_user_assigned_identity.ingestion.principal_id
}

output "data_factory_identity_id" {
  value = azurerm_user_assigned_identity.data_factory.id
}

output "data_factory_identity_client_id" {
  value = azurerm_user_assigned_identity.data_factory.client_id
}

output "data_factory_principal_id" {
  value = azurerm_user_assigned_identity.data_factory.principal_id
}

output "portal_identity_id" {
  value = azurerm_user_assigned_identity.portal.id
}

output "portal_identity_client_id" {
  value = azurerm_user_assigned_identity.portal.client_id
}

output "portal_principal_id" {
  value = azurerm_user_assigned_identity.portal.principal_id
}

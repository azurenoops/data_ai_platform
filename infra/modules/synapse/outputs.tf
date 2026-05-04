output "workspace_id" {
  value = azurerm_synapse_workspace.this.id
}

output "workspace_name" {
  value = azurerm_synapse_workspace.this.name
}

output "serverless_sql_endpoint" {
  value = azurerm_synapse_workspace.this.connectivity_endpoints["sqlOnDemand"]
}

output "workspace_principal_id" {
  value = azurerm_synapse_workspace.this.identity[0].principal_id
}

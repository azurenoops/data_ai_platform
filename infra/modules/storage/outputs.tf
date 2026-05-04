output "storage_id" {
  value = azurerm_storage_account.this.id
}

output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "blob_endpoint" {
  value = azurerm_storage_account.this.primary_blob_endpoint
}

output "dfs_endpoint" {
  value = azurerm_storage_account.this.primary_dfs_endpoint
}

output "filesystem_ids" {
  description = "Map of container name -> ADLS Gen2 filesystem resource ID."
  value       = { for name, fs in azurerm_storage_data_lake_gen2_filesystem.containers : name => fs.id }
}

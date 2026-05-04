output "storage_account_name" {
  value = module.storage.storage_account_name
}

output "storage_account_id" {
  value = module.storage.storage_id
}

output "blob_endpoint" {
  value = module.storage.blob_endpoint
}

output "dfs_endpoint" {
  value = module.storage.dfs_endpoint
}

output "search_endpoint" {
  value = module.search.search_endpoint
}

output "search_name" {
  value = module.search.search_name
}

output "search_id" {
  value = module.search.search_id
}

output "search_principal_id" {
  value = module.search.search_principal_id
}

output "foundry_account_name" {
  value = module.foundry.account_name
}

output "foundry_account_id" {
  value = module.foundry.account_id
}

output "foundry_account_endpoint" {
  value = module.foundry.account_endpoint
}

output "document_intelligence_account_name" {
  value = module.document_intelligence.account_name
}

output "document_intelligence_account_id" {
  value = module.document_intelligence.account_id
}

output "document_intelligence_endpoint" {
  value = module.document_intelligence.endpoint
}

output "app_service_name" {
  value = module.appservice.site_name
}

output "app_service_host_name" {
  value = module.appservice.default_host_name
}

output "app_service_resource_id" {
  value = module.appservice.site_id
}

output "function_app_name" {
  value = module.functions.function_app_name
}

output "function_app_host_name" {
  value = module.functions.default_host_name
}

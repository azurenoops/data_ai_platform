output "search_id" {
  value = azapi_resource.search.id
}

output "search_name" {
  value = azapi_resource.search.name
}

output "search_endpoint" {
  value = "https://${azapi_resource.search.name}.search.windows.net"
}

output "search_principal_id" {
  value = azapi_resource.search.output.identity.principalId
}

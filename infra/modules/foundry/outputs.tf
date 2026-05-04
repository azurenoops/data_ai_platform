output "account_id" {
  value = azapi_resource.account.id
}

output "account_name" {
  value = azapi_resource.account.name
}

output "account_endpoint" {
  value = azapi_resource.account.output.properties.endpoint
}

output "account_principal_id" {
  value = azapi_resource.account.output.identity.principalId
}

output "project_name" {
  value = azapi_resource.project.name
}

output "project_endpoint" {
  value = "${azapi_resource.account.output.properties.endpoint}api/projects/${azapi_resource.project.name}"
}

output "project_principal_id" {
  value = azapi_resource.project.output.identity.principalId
}

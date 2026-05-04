output "function_app_id" {
  value = azapi_resource.function_app.id
}

output "function_app_name" {
  value = azapi_resource.function_app.name
}

output "default_host_name" {
  value = azapi_resource.function_app.output.properties.defaultHostName
}

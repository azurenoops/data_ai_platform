output "function_app_id" {
  value = azurerm_linux_function_app.this.id
}

output "function_app_name" {
  value = azurerm_linux_function_app.this.name
}

output "default_host_name" {
  value = azurerm_linux_function_app.this.default_hostname
}

output "site_id" {
  value = azurerm_linux_web_app.this.id
}

output "site_name" {
  value = azurerm_linux_web_app.this.name
}

output "default_host_name" {
  value = azurerm_linux_web_app.this.default_hostname
}

output "principal_id" {
  description = "User-assigned identity ID (mirrors the Bicep output that was the UAMI ID, not a system-assigned principal)."
  value       = var.user_assigned_identity_id
}

output "plan_id" {
  value = azurerm_service_plan.this.id
}

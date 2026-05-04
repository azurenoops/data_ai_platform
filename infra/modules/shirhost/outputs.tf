output "vm_id" {
  value = azurerm_windows_virtual_machine.this.id
}

output "vm_name" {
  value = azurerm_windows_virtual_machine.this.name
}

output "private_ip" {
  value = azurerm_network_interface.this.private_ip_address
}

output "system_assigned_principal_id" {
  value = azurerm_windows_virtual_machine.this.identity[0].principal_id
}

output "dsc_blob_url" {
  value       = local.use_dsc ? azurerm_storage_blob.shir_dsc_zip[0].url : ""
  description = "URL of the uploaded DSC ZIP (empty when CustomScript install method is used)."
}

output "install_method" {
  value = var.shir_install_method
}

output "admin_password_secret_name" {
  value = azurerm_key_vault_secret.shir_admin_password.name
}

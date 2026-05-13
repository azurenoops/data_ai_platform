output "vnet_id" {
  description = "Resource ID of the VNet."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the VNet."
  value       = azurerm_virtual_network.this.name
}

output "subnet_app_id" {
  description = "Resource ID of the App Service VNet integration subnet."
  value       = azurerm_subnet.app.id
}

output "subnet_functions_id" {
  description = "Resource ID of the Function App VNet integration subnet."
  value       = azurerm_subnet.functions.id
}

output "subnet_pe_id" {
  description = "Resource ID of the private-endpoint subnet (used as subnet_id on every azurerm_private_endpoint in primary.tf)."
  value       = azurerm_subnet.pe.id
}

output "private_dns_zone_ids" {
  description = "Map of private DNS zone IDs keyed by service token (search, cognitiveservices, blob, dfs, vault, sites)."
  value       = { for k, z in azurerm_private_dns_zone.zones : k => z.id }
}

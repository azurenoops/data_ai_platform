output "endpoint_host_name" {
  value = azurerm_cdn_frontdoor_endpoint.this.host_name
}

output "endpoint_url" {
  value = "https://${azurerm_cdn_frontdoor_endpoint.this.host_name}"
}

output "front_door_id_header" {
  description = "X-Azure-FDID value used to lock down App Service IP restrictions to only this Front Door instance."
  value       = azurerm_cdn_frontdoor_profile.this.resource_guid
}

output "profile_id" {
  value = azurerm_cdn_frontdoor_profile.this.id
}

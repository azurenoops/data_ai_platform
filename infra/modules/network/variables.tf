variable "resource_group_name" {
  description = "Name of the resource group that will own the VNet and DNS zones."
  type        = string
}

variable "location" {
  description = "Region for the VNet (DNS zones are global so location is ignored for those)."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "vnet_name" {
  description = "Name of the VNet."
  type        = string
}

variable "vnet_address_space" {
  description = "Address space (CIDR list) for the VNet."
  type        = list(string)
  default     = ["10.42.0.0/16"]
}

variable "subnet_app_address_prefix" {
  description = "CIDR for the App Service VNet-integration subnet (delegated to Microsoft.Web/serverFarms)."
  type        = string
  default     = "10.42.1.0/24"
}

variable "subnet_functions_address_prefix" {
  description = "CIDR for the Function App VNet-integration subnet (delegated to Microsoft.Web/serverFarms)."
  type        = string
  default     = "10.42.2.0/24"
}

variable "subnet_pe_address_prefix" {
  description = "CIDR for the private-endpoint subnet (NIC IPs land here)."
  type        = string
  default     = "10.42.3.0/24"
}

# Map of private DNS zone names keyed by service token. The defaults target Azure US Government -
# override the entire map to retarget at commercial Azure or another sovereign cloud.
#
# Service tokens consumed by primary.tf when creating the PE -> zone link:
#   search             -> Azure AI Search private endpoints
#   cognitiveservices  -> Document Intelligence + Foundry (Cognitive Services umbrella zone)
#   blob, dfs          -> Storage account (future)
#   vault              -> Key Vault (future)
#   sites              -> App Service / Function App inbound PE (future)
variable "private_dns_zone_names" {
  description = "Map of private DNS zone names keyed by service token. Defaults are Azure US Government zone names."
  type        = map(string)
  default = {
    search            = "privatelink.search.windows.us"
    cognitiveservices = "privatelink.cognitiveservices.azure.us"
    blob              = "privatelink.blob.core.usgovcloudapi.net"
    dfs               = "privatelink.dfs.core.usgovcloudapi.net"
    vault             = "privatelink.vaultcore.usgovcloudapi.net"
    sites             = "privatelink.azurewebsites.us"
  }
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "plan_name" {
  type = string
}

variable "site_name" {
  type = string
}

variable "sku" {
  type    = string
  default = "B1"
}

variable "user_assigned_identity_id" {
  type = string
}

variable "user_assigned_identity_client_id" {
  type = string
}

variable "app_insights_connection_string" {
  type      = string
  sensitive = true
}

variable "app_settings" {
  description = "Map of additional app settings to merge in (overrides the base set)."
  type        = map(string)
  default     = {}
}

variable "virtual_network_subnet_id" {
  description = "Optional subnet ID for VNet integration. When set, the app routes outbound traffic through the VNet so it can reach private-endpoint-only resources (AI Search, Document Intelligence, Foundry)."
  type        = string
  default     = null
}

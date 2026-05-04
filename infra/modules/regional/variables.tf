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

variable "resource_token" {
  type = string
}

variable "abbrs" {
  type = map(string)
}

variable "search_sku" {
  type    = string
  default = "standard"
}

variable "app_service_plan_sku" {
  type    = string
  default = "B1"
}

variable "app_insights_connection_string" {
  type      = string
  sensitive = true
}

variable "mcp_server_user_assigned_identity_id" {
  type = string
}

variable "mcp_server_user_assigned_identity_client_id" {
  type = string
}

variable "ingestion_user_assigned_identity_id" {
  type = string
}

variable "ingestion_user_assigned_identity_client_id" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "primary_storage_account_name" {
  type = string
}

variable "app_audience" {
  type = string
}

variable "chat_deployment" {
  type    = string
  default = "gpt-4o"
}

variable "chat_mini_deployment" {
  type    = string
  default = "gpt-4o-mini"
}

variable "embedding_deployment" {
  type    = string
  default = "text-embedding-3-large"
}

variable "cmk_key_uri" {
  type    = string
  default = ""
}

variable "cmk_user_assigned_identity_id" {
  type    = string
  default = ""
}

variable "cmk_user_assigned_identity_client_id" {
  type    = string
  default = ""
}

variable "cmk_key_name" {
  type    = string
  default = ""
}

variable "cmk_key_vault_uri" {
  type    = string
  default = ""
}

variable "storage_sku" {
  type    = string
  default = "Standard_RAGZRS"
}

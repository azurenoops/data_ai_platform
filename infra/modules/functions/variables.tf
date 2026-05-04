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

variable "function_app_name" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "storage_dfs_endpoint" {
  description = "Primary blob endpoint for the storage account, used as the deployment source root."
  type        = string
}

variable "deployment_container_name" {
  type    = string
  default = "deploy"
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
  type    = map(string)
  default = {}
}

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

variable "account_name" {
  type = string
}

variable "project_name" {
  type = string
}

variable "chat_deployment" {
  type = string
}

variable "chat_mini_deployment" {
  type = string
}

variable "embedding_deployment" {
  type = string
}

variable "search_account_id" {
  description = "Resource ID of the AI Search service to wire as a project connection."
  type        = string
}

variable "storage_account_id" {
  description = "Resource ID of the storage account to wire as a project connection."
  type        = string
}

variable "cmk_key_uri" {
  description = "Versionless KV key URL. Empty disables CMK on the AI Services account."
  type        = string
  default     = ""
}

variable "cmk_user_assigned_identity_id" {
  type    = string
  default = ""
}

variable "cmk_user_assigned_identity_client_id" {
  type    = string
  default = ""
}

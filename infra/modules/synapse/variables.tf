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

variable "workspace_name" {
  type = string
}

variable "storage_account_id" {
  description = "Resource ID of the storage account that backs the workspace default datalake."
  type        = string
}

variable "storage_filesystem_id" {
  description = "Resource ID of the ADLS Gen2 filesystem that backs the workspace default datalake. The filesystem is owned by the storage module."
  type        = string
}

variable "sql_admin_login" {
  type = string
}

variable "sql_admin_aad_object_id" {
  description = "Object ID of the Entra principal to grant Synapse Administrator. Empty to skip."
  type        = string
  default     = ""
}

variable "tenant_id" {
  type = string
}

variable "cmk_key_uri" {
  description = "Versionless KV key URL. Empty disables CMK."
  type        = string
  default     = ""
}

variable "cmk_user_assigned_identity_id" {
  description = "UAMI resource ID used for KEK identity. Required when cmk_key_uri is set."
  type        = string
  default     = ""
}

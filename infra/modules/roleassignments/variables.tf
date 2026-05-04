variable "storage_account_id" {
  type = string
}

variable "search_id" {
  type = string
}

variable "foundry_account_id" {
  type = string
}

variable "document_intelligence_account_id" {
  type = string
}

variable "key_vault_id" {
  type = string
}

variable "mcp_server_principal_id" {
  type = string
}

variable "ingestion_principal_id" {
  type = string
}

variable "data_factory_principal_id" {
  type = string
}

variable "dev_principal_id" {
  description = "Object ID of the developer / CI principal (empty to skip)."
  type        = string
  default     = ""
}

variable "cmk_consumer_principal_ids" {
  description = "Principal IDs that need Key Vault Crypto Service Encryption User on the CMK vault. Empty list when CMK is disabled."
  type        = list(string)
  default     = []
}

variable "enable_data_factory_pipelines" {
  description = "When true, grants Data Factory MI the Key Vault Secrets User role (needed to read operator-managed connector secrets at pipeline runtime)."
  type        = bool
  default     = false
}

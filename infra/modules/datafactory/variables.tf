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

variable "factory_name" {
  type = string
}

variable "user_assigned_identity_id" {
  type = string
}

# ---------------------------------------------------------------------------
# Wired-from-root references (required when pipelines are enabled).
# ---------------------------------------------------------------------------

variable "key_vault_id" {
  description = "Resource ID of the platform Key Vault (used for ADF KV linked service)."
  type        = string
  default     = null
}

variable "key_vault_uri" {
  description = "URI of the platform Key Vault (e.g. https://<kv>.vault.azure.net)."
  type        = string
  default     = null
}

variable "key_vault_name" {
  description = "Name of the platform Key Vault (used for the AzureKeyVault linked service display name)."
  type        = string
  default     = null
}

variable "storage_account_name" {
  description = "Name of the platform ADLS Gen2 account (sink for every ADF pipeline)."
  type        = string
  default     = null
}

variable "storage_dfs_endpoint" {
  description = "Primary DFS endpoint of the platform ADLS Gen2 account."
  type        = string
  default     = null
}

variable "data_factory_identity_client_id" {
  description = "Client ID of the user-assigned identity attached to ADF; used by ADF KV linked service for credential reference."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Master switches (mirror the root tfvars surface).
# ---------------------------------------------------------------------------

variable "enable_data_factory_pipelines" {
  type    = bool
  default = false
}

variable "enable_data_factory_schedules" {
  type    = bool
  default = false
}

# ---------------------------------------------------------------------------
# SQL Managed Instance.
# ---------------------------------------------------------------------------

variable "sql_mi_server_fqdn" {
  type    = string
  default = null
}

variable "sql_mi_database" {
  type    = string
  default = null
}

variable "sql_mi_tables" {
  type = list(object({
    schema = string
    name   = string
  }))
  default = []
}

variable "sql_mi_schedule_cron" {
  type    = string
  default = "0 0 4 * * *"
}

# ---------------------------------------------------------------------------
# Azure File Share.
# ---------------------------------------------------------------------------

variable "afs_storage_account_name" {
  type    = string
  default = null
}

variable "afs_share_name" {
  type    = string
  default = null
}

variable "afs_storage_key_secret_name" {
  type    = string
  default = "afs-storage-key"
}

variable "afs_schedule_cron" {
  type    = string
  default = "0 0 5 * * *"
}

# ---------------------------------------------------------------------------
# SharePoint Online lists.
# ---------------------------------------------------------------------------

variable "sharepoint_site_url" {
  type    = string
  default = null
}

variable "sharepoint_lists" {
  type    = list(string)
  default = []
}

variable "sharepoint_aad_app_tenant_id" {
  type    = string
  default = null
}

variable "sharepoint_aad_app_client_id" {
  type    = string
  default = null
}

variable "sharepoint_aad_app_secret_name" {
  type    = string
  default = "sharepoint-list-client-secret"
}

variable "sharepoint_schedule_cron" {
  type    = string
  default = "0 0 6 * * *"
}

# ---------------------------------------------------------------------------
# Dataverse via Synapse Link.
# ---------------------------------------------------------------------------

variable "dataverse_synapselink_path" {
  type    = string
  default = "synapselink"
}

variable "dataverse_schedule_cron" {
  type    = string
  default = "0 0 7 * * *"
}

variable "dataverse_probe_enabled" {
  type    = bool
  default = false
}

# ---------------------------------------------------------------------------
# Self-Hosted Integration Runtime.
# ---------------------------------------------------------------------------

variable "enable_self_hosted_integration_runtime" {
  type    = bool
  default = false
}

variable "self_hosted_integration_runtime_name" {
  type    = string
  default = "shir-onprem"
}

variable "sql_mi_use_shir" {
  type    = bool
  default = false
}

variable "afs_use_shir" {
  type    = bool
  default = false
}

variable "sharepoint_use_shir" {
  type    = bool
  default = false
}

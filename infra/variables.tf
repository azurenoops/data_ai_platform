variable "environment_name" {
  description = "Name of the environment used to seed resource names."
  type        = string

  validation {
    condition     = length(var.environment_name) >= 1 && length(var.environment_name) <= 64
    error_message = "environment_name must be between 1 and 64 characters."
  }
}

variable "location" {
  description = "Primary location for all resources."
  type        = string
}

variable "principal_id" {
  description = "Optional principal ID of a developer to grant data-plane access for local dev. Empty in CI."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tag map applied to every resource for cost reporting / cleanup. The azd-env-name tag is added automatically."
  type        = map(string)
  default     = {}
}

variable "search_sku" {
  description = "SKU for the AI Search service."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["basic", "standard", "standard2", "standard3"], var.search_sku)
    error_message = "search_sku must be one of: basic, standard, standard2, standard3."
  }
}

variable "app_service_plan_sku" {
  description = "SKU for the App Service plan that hosts the MCP server."
  type        = string
  default     = "B1"
}

variable "chat_deployment" {
  description = "Foundry chat model deployment name."
  type        = string
  default     = "gpt-4o"
}

variable "chat_mini_deployment" {
  description = "Foundry chat-mini model deployment name."
  type        = string
  default     = "gpt-4o-mini"
}

variable "embedding_deployment" {
  description = "Foundry embedding model deployment name."
  type        = string
  default     = "text-embedding-3-large"
}

variable "enable_cmk" {
  description = "Enable customer-managed-key (CMK) encryption across Storage, AI Services, Search and Synapse. Requires Key Vault purge protection."
  type        = bool
  default     = false
}

variable "secondary_location" {
  description = "Secondary region for multi-region DR. Empty disables DR."
  type        = string
  default     = ""
}

variable "storage_sku" {
  description = "Storage replication SKU. Auto-promoted to Standard_RAGZRS when DR is enabled."
  type        = string
  default     = "Standard_LRS"

  validation {
    condition     = contains(["Standard_LRS", "Standard_ZRS", "Standard_GRS", "Standard_RAGRS", "Standard_GZRS", "Standard_RAGZRS"], var.storage_sku)
    error_message = "storage_sku must be one of: Standard_LRS, Standard_ZRS, Standard_GRS, Standard_RAGRS, Standard_GZRS, Standard_RAGZRS."
  }
}

variable "front_door_sku" {
  description = "Front Door SKU when DR is enabled."
  type        = string
  default     = "Standard_AzureFrontDoor"

  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.front_door_sku)
    error_message = "front_door_sku must be Standard_AzureFrontDoor or Premium_AzureFrontDoor."
  }
}

# ---------------------------------------------------------------------------
# Data Factory ingestion (opt-in)
#
# All defaults are no-ops so an unmodified `terraform plan` produces the same
# diff as before this surface was added. Operators turn on individual sources
# by setting the per-source connection variables in their tfvars file. See
# docs/INGESTION.md and docs/ingestion/<source>.md for the operator runbook.
# ---------------------------------------------------------------------------

variable "enable_data_factory_pipelines" {
  description = "Master switch: when true, deploy ADF linked services, datasets, and pipelines for the sources whose connection variables are set."
  type        = bool
  default     = false
}

variable "enable_data_factory_schedules" {
  description = "When true (and enable_data_factory_pipelines is also true), deploy tumbling-window triggers using the per-source cron variables."
  type        = bool
  default     = false
}

# ---- SQL Managed Instance ----
variable "sql_mi_server_fqdn" {
  description = "Fully-qualified server name of the source SQL Managed Instance, e.g. 'phwc-sqlmi.public.<dnszone>.database.usgovcloudapi.net,3342'. Leaving null disables the SQL MI pipeline."
  type        = string
  default     = null
}

variable "sql_mi_database" {
  description = "Database name on the SQL Managed Instance."
  type        = string
  default     = null
}

variable "sql_mi_tables" {
  description = "Tables to copy each run. Used as the default value of the pl_sql_mi_to_adls 'tables' parameter."
  type = list(object({
    schema = string
    name   = string
  }))
  default = []
}

variable "sql_mi_schedule_cron" {
  description = "Cron schedule for the SQL MI tumbling-window trigger (UTC). Default 04:00 daily."
  type        = string
  default     = "0 0 4 * * *"
}

# ---- Azure File Share ----
variable "afs_storage_account_name" {
  description = "Source Azure File Share storage account name. Leaving null disables the AFS pipeline."
  type        = string
  default     = null
}

variable "afs_share_name" {
  description = "File share name on the AFS account."
  type        = string
  default     = null
}

variable "afs_storage_key_secret_name" {
  description = "Name of the KV secret holding the AFS storage account key. Operator pre-creates the secret."
  type        = string
  default     = "afs-storage-key"
}

variable "afs_schedule_cron" {
  description = "Cron schedule for the AFS tumbling-window trigger (UTC). Default 05:00 daily."
  type        = string
  default     = "0 0 5 * * *"
}

# ---- SharePoint Online lists ----
variable "sharepoint_site_url" {
  description = "SharePoint Online site URL, e.g. 'https://tenant.sharepoint.us/sites/<site>'. Leaving null disables the SharePoint-list pipeline."
  type        = string
  default     = null
}

variable "sharepoint_lists" {
  description = "List titles to ingest. Each becomes a CopyList iteration."
  type        = list(string)
  default     = []
}

variable "sharepoint_aad_app_tenant_id" {
  description = "Tenant ID of the AAD app registration used by the SharePoint Online list connector."
  type        = string
  default     = null
}

variable "sharepoint_aad_app_client_id" {
  description = "Client ID of the AAD app registration used by the SharePoint Online list connector."
  type        = string
  default     = null
}

variable "sharepoint_aad_app_secret_name" {
  description = "Name of the KV secret holding the AAD app-registration client secret. Operator pre-creates the secret."
  type        = string
  default     = "sharepoint-list-client-secret"
}

variable "sharepoint_schedule_cron" {
  description = "Cron schedule for the SharePoint-lists tumbling-window trigger (UTC). Default 06:00 daily."
  type        = string
  default     = "0 0 6 * * *"
}

# ---- Dataverse via Synapse Link ----
variable "dataverse_synapselink_path" {
  description = "Subpath under curated/ where Synapse Link for Dataverse writes. Used by the marker pipeline and Synapse views."
  type        = string
  default     = "synapselink"
}

variable "dataverse_schedule_cron" {
  description = "Cron schedule for the Dataverse connectivity-check trigger (UTC). Default 07:00 daily."
  type        = string
  default     = "0 0 7 * * *"
}

variable "dataverse_probe_enabled" {
  description = "When true, run a post-deploy null_resource probe (`az storage fs file list`) against curated/<dataverse_synapselink_path>. Disabled by default so first-time apply stays green before Synapse Link is wired in Power Platform."
  type        = bool
  default     = false
}

# ---- Self-Hosted Integration Runtime ----
variable "enable_self_hosted_integration_runtime" {
  description = "When true, deploy a Self-Hosted Integration Runtime resource on the Data Factory. Required for sources that live behind firewall / private endpoints."
  type        = bool
  default     = false
}

variable "self_hosted_integration_runtime_name" {
  description = "Display name of the SHIR (must be ≤63 chars per ADF naming rules)."
  type        = string
  default     = "shir-onprem"

  validation {
    condition     = length(var.self_hosted_integration_runtime_name) <= 63
    error_message = "self_hosted_integration_runtime_name must be 63 characters or fewer."
  }
}

variable "sql_mi_use_shir" {
  description = "When true (and SHIR is enabled), the SQL MI linked service routes via the SHIR instead of the auto-resolve Azure IR."
  type        = bool
  default     = false
}

variable "afs_use_shir" {
  description = "When true (and SHIR is enabled), the AFS linked service routes via the SHIR. Useful when the AFS account is firewall-restricted."
  type        = bool
  default     = false
}

variable "sharepoint_use_shir" {
  description = "When true (and SHIR is enabled), the SharePoint Online list linked service routes via the SHIR."
  type        = bool
  default     = false
}

# ---- SHIR host VM (opt-in) ----
variable "enable_shir_host_vm" {
  description = "When true, deploy a hardened Windows Server 2022 VM that hosts the SHIR shim. Requires enable_self_hosted_integration_runtime=true and shir_host_subnet_id."
  type        = bool
  default     = false
}

variable "shir_host_subnet_id" {
  description = "Resource ID of an existing subnet to deploy the SHIR host VM into. Required when enable_shir_host_vm=true."
  type        = string
  default     = null
}

variable "shir_host_bastion_subnet_address_prefix" {
  description = "CIDR allowed inbound RDP into the SHIR host VM (typically the Bastion subnet)."
  type        = string
  default     = "10.0.255.0/27"
}

variable "shir_host_vm_size" {
  description = "Azure VM SKU for the SHIR host."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "shir_host_vm_admin_username" {
  description = "Local administrator username on the SHIR host VM."
  type        = string
  default     = "shiradmin"
}

variable "shir_installer_url" {
  description = "URL of the Microsoft Integration Runtime MSI installer. Override to host internally for sovereign-cloud egress profiles."
  type        = string
  default     = "https://download.microsoft.com/download/E/4/7/E4771905-1079-445B-8BF9-8A1A075D8A10/IntegrationRuntime_5.x.msi"
}

variable "shir_install_method" {
  description = "How the SHIR shim is installed on the host VM. 'DSC' (default) is idempotent and self-heals on auth-key rotation; 'CustomScript' is the sovereign-cloud fallback when DSC pull is unreliable."
  type        = string
  default     = "DSC"

  validation {
    condition     = contains(["DSC", "CustomScript"], var.shir_install_method)
    error_message = "shir_install_method must be DSC or CustomScript."
  }
}

# ---------------------------------------------------------------------------
# Alerting (opt-in)
#
# An empty alert_email_recipients list disables every alert resource. Set the
# list to one or more addresses to deploy the platform_ops action group plus
# the per-source alert catalog described in docs/INGESTION.md §8.
# ---------------------------------------------------------------------------

variable "alert_email_recipients" {
  description = "Email addresses for the platform_ops action group. Empty list disables all alerting."
  type        = list(string)
  default     = []
}

variable "alert_webhook_url" {
  description = "Optional ServiceNow / Teams webhook URL for the platform_ops action group."
  type        = string
  default     = null
}

variable "kv_secret_expiry_threshold_days" {
  description = "Days-out warning for KV secret expiry alerts."
  type        = number
  default     = 30
}

variable "function_failure_rate_threshold_pct" {
  description = "Function App HTTP 5xx rate threshold (percent) over a 15-minute window."
  type        = number
  default     = 5
}

variable "embedding_throttle_threshold_count" {
  description = "Foundry embedding-deployment 429-response threshold count over a 15-minute window."
  type        = number
  default     = 10
}

variable "search_ingestion_latency_p95_ms" {
  description = "P95 of ingestion.IndexLatencyMs (in milliseconds) above which the Search ingestion latency alert fires."
  type        = number
  default     = 60000
}

variable "shir_host_cpu_threshold_pct" {
  description = "Sustained CPU percentage threshold for the SHIR host VM CPU alert."
  type        = number
  default     = 90
}

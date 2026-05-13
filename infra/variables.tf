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
# Networking (VNet + private endpoints)
#
# These drive the network module that owns the VNet, three subnets
# (app / functions / pe), and the private DNS zones used by every PE in
# primary.tf. Defaults use a 10.42.0.0/16 space that is unlikely to overlap
# with hub/spoke networks; override in envs/*.tfvars if you have a tenant-
# assigned CIDR.
#
# For hub-and-spoke topologies where networking is pre-provisioned by a
# platform team, set use_existing_vnet=true and pass the subnet + DNS zone
# IDs through the existing_* variables. The network module is then skipped
# entirely and the PEs land in the supplied subnet.
# ---------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "Address space (CIDR list) for the platform VNet. Ignored when use_existing_vnet=true."
  type        = list(string)
  default     = ["10.42.0.0/16"]
}

variable "subnet_app_address_prefix" {
  description = "CIDR for the App Service VNet-integration subnet (delegated to Microsoft.Web/serverFarms). Ignored when use_existing_vnet=true."
  type        = string
  default     = "10.42.1.0/24"
}

variable "subnet_functions_address_prefix" {
  description = "CIDR for the Function App VNet-integration subnet (delegated to Microsoft.Web/serverFarms). Ignored when use_existing_vnet=true."
  type        = string
  default     = "10.42.2.0/24"
}

variable "subnet_pe_address_prefix" {
  description = "CIDR for the private-endpoint subnet (NIC IPs land here). Ignored when use_existing_vnet=true."
  type        = string
  default     = "10.42.3.0/24"
}

variable "use_existing_vnet" {
  description = "When true, skip creating the VNet, subnets, and private DNS zones. Consume external IDs via the existing_* variables below. Use this in hub-and-spoke topologies where networking is pre-provisioned by a platform team."
  type        = bool
  default     = false
}

variable "existing_subnet_app_id" {
  description = "Resource ID of an existing subnet for App Service VNet integration. Required when use_existing_vnet=true. MUST be delegated to Microsoft.Web/serverFarms."
  type        = string
  default     = null
}

variable "existing_subnet_functions_id" {
  description = "Resource ID of an existing subnet for Function App VNet integration. Required when use_existing_vnet=true. MUST be delegated to Microsoft.Web/serverFarms."
  type        = string
  default     = null
}

variable "existing_subnet_pe_id" {
  description = "Resource ID of an existing subnet that will host private-endpoint NICs. Required when use_existing_vnet=true. private_endpoint_network_policies SHOULD be Disabled."
  type        = string
  default     = null
}

variable "existing_private_dns_zone_ids" {
  description = "Map of pre-existing private DNS zone IDs keyed by service token. Required when use_existing_vnet=true. Required keys: 'search' and 'cognitiveservices'. Optional reserved keys for future PE phases: 'blob', 'dfs', 'vault', 'sites'."
  type        = map(string)
  default     = {}
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

# ---------------------------------------------------------------------------
# Re-use existing resources (skip create, reference via data source)
#
# Each toggle below flips a root-level module from "create" to "lookup". The
# module is still composed (so its outputs are stable), but Terraform skips
# the underlying Azure resource and resolves IDs / endpoints from a data
# source instead. Use these when the named resource already exists in the
# target subscription (e.g. shared platform Foundry account, shared Search
# service) and you want Terraform to wire app config + RBAC against it
# without taking ownership of the resource lifecycle.
#
# When a toggle is true the matching `existing_*_name` and
# `existing_*_resource_group_name` variables must point at the live resource.
# Names default to the same `local.names.*` value Terraform would have used
# when creating from scratch, so a previously-Terraform-created resource can
# be "adopted" by flipping the toggle without re-naming.
# ---------------------------------------------------------------------------

# ---- AI Search ----
variable "use_existing_search" {
  description = "When true, skip creating the primary AI Search service and reference an existing one. Required when use_existing_search=true: existing_search_name. Optional: existing_search_resource_group_name (defaults to the primary RG)."
  type        = bool
  default     = false
}

variable "existing_search_name" {
  description = "Name of the existing AI Search service to reference when use_existing_search=true. Defaults to the auto-generated name local.names.search when null."
  type        = string
  default     = null
}

variable "existing_search_resource_group_name" {
  description = "Resource group name of the existing AI Search service. Defaults to the primary RG (rg-<environment_name>) when null."
  type        = string
  default     = null
}

# ---- AI Foundry (Cognitive Services account + project) ----
variable "use_existing_foundry_account" {
  description = "When true, skip creating the primary Foundry account, project, model deployments, and project connections; reference the existing account instead. Model deployments (chat / chat-mini / embedding) and project connections (aisearch, datalake) must already exist on the referenced account."
  type        = bool
  default     = false
}

variable "existing_foundry_account_name" {
  description = "Name of the existing Foundry (Cognitive Services AIServices) account. Defaults to local.names.foundry_account when null."
  type        = string
  default     = null
}

variable "existing_foundry_account_resource_group_name" {
  description = "Resource group name of the existing Foundry account. Defaults to the primary RG when null."
  type        = string
  default     = null
}

variable "existing_foundry_project_name" {
  description = "Project name on the existing Foundry account, used to build the project endpoint URL ('{endpoint}api/projects/{project}'). Defaults to local.names.foundry_project when null."
  type        = string
  default     = null
}

# ---- Data Factory ----
variable "use_existing_data_factory" {
  description = "When true, skip creating the Data Factory and reference an existing one. Linked services, datasets, pipelines, triggers, and SHIR resources defined under infra/modules/datafactory/ will NOT be applied to the referenced factory; manage those out-of-band or with a future module refactor. Incompatible with enable_data_factory_pipelines=true, enable_self_hosted_integration_runtime=true, and enable_shir_host_vm=true."
  type        = bool
  default     = false
}

variable "existing_data_factory_name" {
  description = "Name of the existing Data Factory. Defaults to local.names.data_factory when null."
  type        = string
  default     = null
}

variable "existing_data_factory_resource_group_name" {
  description = "Resource group name of the existing Data Factory. Defaults to the primary RG when null."
  type        = string
  default     = null
}

# ---- Front Door (DR only) ----
variable "use_existing_front_door" {
  description = "When true (and DR is enabled via secondary_location), skip creating the Front Door profile, endpoint, origin group, origins, and route; reference an existing profile + endpoint instead. Routes, origin groups, and origins on the referenced profile must be managed out-of-band. No-op when DR is disabled."
  type        = bool
  default     = false
}

variable "existing_front_door_profile_name" {
  description = "Name of the existing Front Door (CDN profile, Standard or Premium AzureFrontDoor SKU). Defaults to local.names.front_door when null."
  type        = string
  default     = null
}

variable "existing_front_door_endpoint_name" {
  description = "Name of the AFD endpoint on the existing profile. Defaults to '{profile_name}-ep' to match the auto-generated naming, when null."
  type        = string
  default     = null
}

variable "existing_front_door_resource_group_name" {
  description = "Resource group name of the existing Front Door profile. Defaults to the primary RG when null."
  type        = string
  default     = null
}

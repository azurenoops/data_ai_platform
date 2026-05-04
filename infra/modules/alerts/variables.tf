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

# ---------------------------------------------------------------------------
# Alerting (opt-in via non-empty alert_email_recipients).
# ---------------------------------------------------------------------------

variable "alert_email_recipients" {
  description = "Email addresses for the platform_ops action group. Empty list disables all alerting."
  type        = list(string)
  default     = []
}

variable "alert_webhook_url" {
  description = "Optional webhook URL for the platform_ops action group."
  type        = string
  default     = null
}

variable "kv_secret_expiry_threshold_days" {
  type    = number
  default = 30
}

variable "function_failure_rate_threshold_pct" {
  type    = number
  default = 5
}

variable "embedding_throttle_threshold_count" {
  type    = number
  default = 10
}

variable "search_ingestion_latency_p95_ms" {
  type    = number
  default = 60000
}

variable "shir_host_cpu_threshold_pct" {
  type    = number
  default = 90
}

# ---------------------------------------------------------------------------
# Source-conditional gates (alerts skipped when scope is null).
# ---------------------------------------------------------------------------

variable "log_analytics_id" {
  description = "Resource ID of the Log Analytics workspace (scope for scheduled-query alerts that run KQL over diagnostics)."
  type        = string
}

variable "app_insights_id" {
  description = "Resource ID of the Application Insights component (scope for the customMetrics-based ingestion latency alert)."
  type        = string
}

variable "key_vault_id" {
  type    = string
  default = null
}

variable "tracked_secrets" {
  description = "List of KV secret names to monitor for upcoming expiry."
  type        = list(string)
  default     = []
}

variable "function_app_id" {
  type    = string
  default = null
}

variable "data_factory_id" {
  type    = string
  default = null
}

variable "foundry_account_id" {
  type    = string
  default = null
}

variable "shir_host_vm_id" {
  type    = string
  default = null
}

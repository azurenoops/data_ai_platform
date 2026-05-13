# ---------------------------------------------------------------------------
# `platform_ops` action group + alert catalog.
#
# Empty `alert_email_recipients` (the default) deploys ZERO alert resources.
# When at least one recipient is supplied, the shared `platform_ops` action
# group is created and each alert is gated on its own source-specific
# variable so the catalog scales with what the rest of the stack actually
# deploys (no orphan alerts for resources that don't exist).
#
# The action group is named `platform_ops` from day one (not `secret_rotation`)
# so future alerts attach to the same group without a rename + state-mv.
# ---------------------------------------------------------------------------

locals {
  alerts_enabled   = length(var.alert_email_recipients) > 0
  alerts_action_id = local.alerts_enabled ? azurerm_monitor_action_group.platform_ops[0].id : ""
  # Gate the per-secret expiry alerts on alerts_enabled only. The caller is
  # responsible for passing a non-null key_vault_id and a non-empty
  # tracked_secrets list when alerts are enabled; if tracked_secrets is empty
  # the for_each below iterates zero times, so no resources are created.
  monitor_kv_alerts = local.alerts_enabled
}

resource "azurerm_monitor_action_group" "platform_ops" {
  count = local.alerts_enabled ? 1 : 0

  name                = "platform_ops"
  resource_group_name = var.resource_group_name
  short_name          = "platops"
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = toset(var.alert_email_recipients)
    content {
      name          = "email-${replace(email_receiver.value, "/[^a-zA-Z0-9]/", "-")}"
      email_address = email_receiver.value
    }
  }

  dynamic "webhook_receiver" {
    for_each = var.alert_webhook_url != null ? [var.alert_webhook_url] : []
    content {
      name        = "platform-webhook"
      service_uri = webhook_receiver.value
    }
  }
}

# ---- 1. KV secret expiry (per tracked secret) ------------------------------

resource "azurerm_monitor_metric_alert" "kv_secret_expiry" {
  for_each = local.monitor_kv_alerts ? toset(var.tracked_secrets) : toset([])

  name                = "kv-secret-expiry-${each.value}"
  resource_group_name = var.resource_group_name
  scopes              = [var.key_vault_id]
  description         = "Fires when KV secret '${each.value}' is within ${var.kv_secret_expiry_threshold_days} days of expiring."
  frequency           = "PT1H"
  window_size         = "PT1H"
  severity            = 2
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.KeyVault/vaults"
    metric_name      = "SecretNearExpiry"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = 0

    dimension {
      name     = "SecretName"
      operator = "Include"
      values   = [each.value]
    }
  }

  action {
    action_group_id = local.alerts_action_id
  }
}

# ---- 2. Function App failure rate ------------------------------------------

resource "azurerm_monitor_metric_alert" "function_failure_rate" {
  count = local.alerts_enabled ? 1 : 0

  name                = "function-failure-rate"
  resource_group_name = var.resource_group_name
  scopes              = [var.function_app_id]
  description         = "Fires when the ingestion Function App's HTTP 5xx rate exceeds ${var.function_failure_rate_threshold_pct}% over 15 minutes."
  frequency           = "PT5M"
  window_size         = "PT15M"
  severity            = 2
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = var.function_failure_rate_threshold_pct
  }

  action {
    action_group_id = local.alerts_action_id
  }
}

# ---- 3. ADF pipeline failure (scheduled query over LA) ---------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "adf_pipeline_failure" {
  count = local.alerts_enabled ? 1 : 0

  name                 = "adf-pipeline-failure"
  resource_group_name  = var.resource_group_name
  location             = var.location
  description          = "Fires when any ADF pipeline run failed in the last hour."
  evaluation_frequency = "PT15M"
  window_duration      = "PT1H"
  severity             = 2
  tags                 = var.tags
  scopes               = [var.log_analytics_id]

  criteria {
    query                   = <<-KQL
      AzureDiagnostics
      | where ResourceProvider == "MICROSOFT.DATAFACTORY"
      | where Category == "PipelineRuns"
      | where status_s == "Failed"
    KQL
    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Count"
  }

  action {
    action_groups = [local.alerts_action_id]
  }
}

# ---- 4. Foundry embedding deployment 429s ----------------------------------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "embedding_throttle" {
  count = local.alerts_enabled ? 1 : 0

  name                 = "embedding-throttle"
  resource_group_name  = var.resource_group_name
  location             = var.location
  description          = "Fires when Foundry embedding deployment returns more than ${var.embedding_throttle_threshold_count} HTTP 429s in 15 minutes."
  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"
  severity             = 2
  tags                 = var.tags
  scopes               = [var.log_analytics_id]

  criteria {
    query                   = <<-KQL
      AzureDiagnostics
      | where ResourceProvider == "MICROSOFT.COGNITIVESERVICES"
      | where ResultSignature == "429"
    KQL
    operator                = "GreaterThan"
    threshold               = var.embedding_throttle_threshold_count
    time_aggregation_method = "Count"
  }

  action {
    action_groups = [local.alerts_action_id]
  }
}

# ---- 5. Search ingestion latency P95 (App Insights customMetrics) ----------

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "search_ingestion_latency" {
  count = local.alerts_enabled ? 1 : 0

  name                 = "search-ingestion-latency"
  resource_group_name  = var.resource_group_name
  location             = var.location
  description          = "Fires when the P95 of ingestion.IndexLatencyMs (emitted by DocumentIngestionPipeline) exceeds ${var.search_ingestion_latency_p95_ms} ms over 30 minutes."
  evaluation_frequency = "PT5M"
  window_duration      = "PT30M"
  severity             = 3
  tags                 = var.tags
  scopes               = [var.app_insights_id]

  criteria {
    query                   = <<-KQL
      customMetrics
      | where name == "ingestion.IndexLatencyMs"
      | summarize p95 = percentile(value, 95)
    KQL
    operator                = "GreaterThan"
    threshold               = var.search_ingestion_latency_p95_ms
    time_aggregation_method = "Maximum"
    metric_measure_column   = "p95"
  }

  action {
    action_groups = [local.alerts_action_id]
  }
}

# ---- 6. SHIR host CPU sustained ---------------------------------------------

resource "azurerm_monitor_metric_alert" "shir_host_cpu" {
  count = (local.alerts_enabled && var.shir_host_vm_id != null) ? 1 : 0

  name                = "shir-host-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [var.shir_host_vm_id]
  description         = "Fires when the SHIR host VM CPU exceeds ${var.shir_host_cpu_threshold_pct}% sustained over 15 minutes."
  frequency           = "PT5M"
  window_size         = "PT15M"
  severity            = 3
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.shir_host_cpu_threshold_pct
  }

  action {
    action_group_id = local.alerts_action_id
  }
}

# ---------------------------------------------------------------------------
# Tumbling-window schedule triggers (opt-in via enable_data_factory_schedules).
#
# One trigger per enabled pipeline. Each is gated on both the schedules
# master switch and the same per-source enable check that gates the pipeline
# itself, so a trigger for a non-deployed pipeline never appears in the plan.
#
# Default cron schedules are staggered (04:00 SQL MI, 05:00 AFS, 06:00
# SharePoint, 07:00 Dataverse UTC) to avoid concurrent runs on the
# auto-resolve Azure IR.
# ---------------------------------------------------------------------------

resource "azurerm_data_factory_trigger_schedule" "sql_mi" {
  count = local.enable_schedules && local.enable_sqlmi ? 1 : 0

  name            = "trg_sql_mi_daily"
  data_factory_id = azurerm_data_factory.this.id
  description     = "Daily run of pl_sql_mi_to_adls."
  pipeline_name   = azapi_resource.sql_mi_pipeline[0].name
  frequency       = "Day"
  interval        = 1
  schedule {
    hours   = [tonumber(split(" ", var.sql_mi_schedule_cron)[2])]
    minutes = [tonumber(split(" ", var.sql_mi_schedule_cron)[1])]
  }
}

resource "azurerm_data_factory_trigger_schedule" "afs" {
  count = local.enable_schedules && local.enable_afs ? 1 : 0

  name            = "trg_afs_daily"
  data_factory_id = azurerm_data_factory.this.id
  description     = "Daily run of pl_afs_to_adls."
  pipeline_name   = azapi_resource.afs_pipeline[0].name
  frequency       = "Day"
  interval        = 1
  schedule {
    hours   = [tonumber(split(" ", var.afs_schedule_cron)[2])]
    minutes = [tonumber(split(" ", var.afs_schedule_cron)[1])]
  }
}

resource "azurerm_data_factory_trigger_schedule" "sharepoint" {
  count = local.enable_schedules && local.enable_sharepoint ? 1 : 0

  name            = "trg_sharepoint_daily"
  data_factory_id = azurerm_data_factory.this.id
  description     = "Daily run of pl_sharepoint_lists_to_adls."
  pipeline_name   = azapi_resource.sharepoint_pipeline[0].name
  frequency       = "Day"
  interval        = 1
  schedule {
    hours   = [tonumber(split(" ", var.sharepoint_schedule_cron)[2])]
    minutes = [tonumber(split(" ", var.sharepoint_schedule_cron)[1])]
  }
}

resource "azurerm_data_factory_trigger_schedule" "dataverse" {
  count = local.enable_schedules && local.enable_dataverse ? 1 : 0

  name            = "trg_dataverse_daily"
  data_factory_id = azurerm_data_factory.this.id
  description     = "Daily run of pl_dataverse_via_synapselink (connectivity check)."
  pipeline_name   = azapi_resource.dataverse_pipeline[0].name
  frequency       = "Day"
  interval        = 1
  schedule {
    hours   = [tonumber(split(" ", var.dataverse_schedule_cron)[2])]
    minutes = [tonumber(split(" ", var.dataverse_schedule_cron)[1])]
  }
}

output "factory_id" {
  value = azurerm_data_factory.this.id
}

output "factory_name" {
  value = azurerm_data_factory.this.name
}

output "system_assigned_principal_id" {
  value = azurerm_data_factory.this.identity[0].principal_id
}

# ---- Pipeline / linked service / trigger inventory (for post-provision logs) ----

output "linked_service_names" {
  description = "Names of all linked services deployed by this module (excluding the always-on AutoResolveIntegrationRuntime)."
  value = compact([
    local.enable_pipelines ? azurerm_data_factory_linked_custom_service.adls[0].name : "",
    local.enable_kv_ls ? azurerm_data_factory_linked_custom_service.kv[0].name : "",
    local.enable_sqlmi ? azurerm_data_factory_linked_custom_service.sqlmi[0].name : "",
    local.enable_afs ? azurerm_data_factory_linked_custom_service.afs[0].name : "",
    local.enable_sharepoint ? azurerm_data_factory_linked_custom_service.sharepoint[0].name : "",
  ])
}

output "pipeline_names" {
  description = "Names of all pipelines deployed by this module."
  value = compact([
    local.enable_sqlmi ? azapi_resource.sql_mi_pipeline[0].name : "",
    local.enable_afs ? azapi_resource.afs_pipeline[0].name : "",
    local.enable_sharepoint ? azapi_resource.sharepoint_pipeline[0].name : "",
    local.enable_dataverse ? azapi_resource.dataverse_pipeline[0].name : "",
  ])
}

output "trigger_names" {
  description = "Names of all schedule triggers deployed by this module."
  value = compact([
    (local.enable_schedules && local.enable_sqlmi) ? azurerm_data_factory_trigger_schedule.sql_mi[0].name : "",
    (local.enable_schedules && local.enable_afs) ? azurerm_data_factory_trigger_schedule.afs[0].name : "",
    (local.enable_schedules && local.enable_sharepoint) ? azurerm_data_factory_trigger_schedule.sharepoint[0].name : "",
    (local.enable_schedules && local.enable_dataverse) ? azurerm_data_factory_trigger_schedule.dataverse[0].name : "",
  ])
}

output "self_hosted_integration_runtime_name" {
  description = "Display name of the SHIR resource (empty when SHIR is disabled)."
  value       = local.enable_shir ? azurerm_data_factory_integration_runtime_self_hosted.this[0].name : ""
}

output "self_hosted_integration_runtime_primary_key" {
  description = "Primary auth key for the SHIR. Pass to `dmgcmd.exe -RegisterNewNode` on the host VM."
  value       = local.enable_shir ? azurerm_data_factory_integration_runtime_self_hosted.this[0].primary_authorization_key : ""
  sensitive   = true
}

output "self_hosted_integration_runtime_secondary_key" {
  description = "Secondary auth key for the SHIR. Use during key rotation."
  value       = local.enable_shir ? azurerm_data_factory_integration_runtime_self_hosted.this[0].secondary_authorization_key : ""
  sensitive   = true
}

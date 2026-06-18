# ---------------------------------------------------------------------------
# SQL Managed Instance ingestion (pl_sql_mi_to_adls).
#
# Gated by enable_data_factory_pipelines AND non-null sql_mi_server_fqdn /
# sql_mi_database. Linked service uses MI auth; SQL MI access requires an
# operator T-SQL step (`CREATE USER [<adf-uami>] FROM EXTERNAL PROVIDER`)
# documented in docs/ingestion/sql-managed-instance.md.
# ---------------------------------------------------------------------------

locals {
  sqlmi_pipeline_props = jsondecode(file("${path.module}/../../datafactory/pipelines/pl_sql_mi_to_adls.json")).properties
}

resource "azurerm_data_factory_linked_custom_service" "sqlmi" {
  count = local.enable_sqlmi ? 1 : 0

  name            = "ls_sqlmi"
  data_factory_id = azurerm_data_factory.this.id
  type            = "AzureSqlMI"
  description     = "Source SQL Managed Instance. AAD MI auth via the Data Factory user-assigned identity."

  dynamic "integration_runtime" {
    for_each = (local.enable_shir && var.sql_mi_use_shir) ? [1] : []
    content {
      name = local.shir_name
    }
  }

  type_properties_json = jsonencode({
    connectionString = {
      type  = "SecureString"
      value = "data source=${var.sql_mi_server_fqdn};initial catalog=${var.sql_mi_database};"
    }
    authenticationType = "SystemAssignedManagedIdentity"
  })
}

resource "azurerm_data_factory_custom_dataset" "sqlmi_table" {
  count = local.enable_sqlmi ? 1 : 0

  name            = "ds_sqlmi_table"
  data_factory_id = azurerm_data_factory.this.id
  type            = "AzureSqlMITable"

  linked_service {
    name = azurerm_data_factory_linked_custom_service.sqlmi[0].name
  }

  parameters = {
    schemaName = "dbo"
    tableName  = "default"
  }

  type_properties_json = jsonencode({
    schema = "@dataset().schemaName"
    table  = "@dataset().tableName"
  })
}

# Pipeline: deploy via azapi so the complex `tables` parameter (array of objects)
# can carry an operator-tunable default. azurerm_data_factory_pipeline only
# supports map(string) for parameters, which collapses array defaults to JSON
# strings and breaks `@pipeline().parameters.tables` expressions in the activity.
resource "azapi_resource" "sql_mi_pipeline" {
  count = local.enable_sqlmi ? 1 : 0

  type      = "Microsoft.DataFactory/factories/pipelines@2018-06-01"
  parent_id = azurerm_data_factory.this.id
  name      = "pl_sql_mi_to_adls"

  body = {
    properties = merge(local.sqlmi_pipeline_props, {
      parameters = merge(
        try(local.sqlmi_pipeline_props.parameters, {}),
        {
          tables = {
            type         = "array"
            defaultValue = length(var.sql_mi_tables) > 0 ? var.sql_mi_tables : local.sqlmi_pipeline_props.parameters.tables.defaultValue
          }
        }
      )
    })
  }

  depends_on = [
    azurerm_data_factory_custom_dataset.sqlmi_table,
    azurerm_data_factory_custom_dataset.adls_parquet,
  ]
}

# ---------------------------------------------------------------------------
# Dataverse via Synapse Link (pl_dataverse_via_synapselink).
#
# Synapse Link itself is provisioned from the Power Platform admin center
# (no Terraform path exists). This module only deploys:
#   - the connectivity-marker pipeline (verifies the Synapse Link path
#     exists in ADLS curated/<dataverse_synapselink_path>),
#   - the Synapse-Link root dataset that the pipeline reads,
#   - an OPTIONAL post-deploy probe (`az storage fs file list`) that fails
#     loudly when Synapse Link has not been wired yet (var.dataverse_probe_enabled).
#
# See docs/ingestion/dataverse.md for the operator runbook.
# ---------------------------------------------------------------------------

locals {
  dataverse_pipeline_props = jsondecode(file("${path.module}/../../datafactory/pipelines/pl_dataverse_via_synapselink.json")).properties
}

resource "azurerm_data_factory_custom_dataset" "synapselink_root" {
  count = local.enable_dataverse ? 1 : 0

  name            = "ds_adls_synapselink_root"
  data_factory_id = azurerm_data_factory.this.id
  type            = "Binary"

  linked_service {
    name = azurerm_data_factory_linked_custom_service.adls[0].name
  }

  type_properties_json = jsonencode({
    location = {
      type       = "AzureBlobFSLocation"
      fileSystem = "curated"
      folderPath = var.dataverse_synapselink_path
    }
  })
}

resource "azapi_resource" "dataverse_pipeline" {
  count = local.enable_dataverse ? 1 : 0

  type      = "Microsoft.DataFactory/factories/pipelines@2018-06-01"
  parent_id = azurerm_data_factory.this.id
  name      = "pl_dataverse_via_synapselink"

  body = {
    properties = local.dataverse_pipeline_props
  }

  depends_on = [
    azurerm_data_factory_custom_dataset.synapselink_root,
  ]
}

# Optional post-deploy probe: validate that the Synapse Link path actually
# exists in ADLS. Disabled by default so first-time `terraform apply` succeeds
# before the operator wires up Synapse Link in Power Platform.
resource "null_resource" "synapselink_path_probe" {
  count = local.enable_dataverse && var.dataverse_probe_enabled ? 1 : 0

  triggers = {
    storage_account = var.storage_account_name
    path            = var.dataverse_synapselink_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      az storage fs file list \
        --auth-mode login \
        --file-system curated \
        --account-name ${var.storage_account_name} \
        --path "${var.dataverse_synapselink_path}" \
        --num-results 1 \
        > /dev/null
    EOT
  }

  depends_on = [
    azapi_resource.dataverse_pipeline,
  ]
}

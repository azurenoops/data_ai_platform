# ---------------------------------------------------------------------------
# Self-Hosted Integration Runtime (opt-in).
#
# Required for sources that live behind firewall / private endpoints. The
# auth keys are emitted as sensitive outputs so the operator can register the
# SHIR shim on a separately-provisioned host VM (see infra/modules/shirhost
# for an opt-in turnkey host).
# ---------------------------------------------------------------------------

resource "azurerm_data_factory_integration_runtime_self_hosted" "this" {
  count = local.enable_shir ? 1 : 0

  name            = var.self_hosted_integration_runtime_name
  data_factory_id = azurerm_data_factory.this.id
  description     = "Self-Hosted Integration Runtime for sources behind firewall / private endpoints. Register the shim on a Windows host with `dmgcmd.exe -RegisterNewNode <auth-key>`."
}

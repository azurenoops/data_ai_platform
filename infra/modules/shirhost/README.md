# `shirhost` Terraform module

Provisions a hardened Windows Server 2022 VM that hosts the
[Self-Hosted Integration Runtime (SHIR)](https://learn.microsoft.com/azure/data-factory/create-self-hosted-integration-runtime)
shim for sources behind firewall / private endpoints.

## What it deploys

| Resource | Purpose |
| --- | --- |
| `azurerm_network_security_group` + `azurerm_network_interface_security_group_association` | Inbound 3389/TCP from `var.bastion_subnet_address_prefix` only; deny-all otherwise. |
| `azurerm_network_interface` | Placed in the operator-supplied `var.subnet_id`; no public IP. |
| `azurerm_windows_virtual_machine` | Windows Server 2022 Datacenter Azure Edition; Trusted Launch (`secure_boot_enabled`, `vtpm_enabled`); system-assigned identity. |
| `random_password` + `azurerm_key_vault_secret` (`shir-host-admin-password`) | Auto-generated local admin credential, stored in the platform Key Vault. |
| `azurerm_storage_blob` (`dsc/shir/InstallShir.zip`) | DSC ZIP uploaded into the existing `deploy/` filesystem (DSC install method only). |
| `azurerm_role_assignment` (`Storage Blob Data Reader`) | Grants the VM's system-assigned identity read on the storage account so DSC can fetch the ZIP via MI (no SAS). |
| `azurerm_virtual_machine_extension` (DSC **or** CustomScript) | Idempotent SHIR install + register. DSC is the default; CustomScript is a sovereign-cloud fallback. |
| `azurerm_virtual_machine_extension` (`AzureMonitorWindowsAgent`) | Defender / patch / metric telemetry into Log Analytics. |

## Out of scope

- VNet, subnet, and Bastion provisioning. Operator supplies an existing
  subnet via `var.subnet_id`.
- AD service-account creation for domain join. The DSC config installs
  RSAT-AD-Tools so the operator can later opt-in to domain join out-of-band.

## Building the DSC ZIP

When `shir_install_method = "DSC"` (the default), `azurerm_storage_blob.shir_dsc_zip`
uploads the file at `var.dsc_zip_path`. Build it locally before
`terraform apply`:

```powershell
pwsh ./infra/modules/shirhost/dsc/build-dsc.ps1
```

That runs the configuration in `InstallShir.ps1`, downloads the
`xPSDesiredStateConfiguration` module dependency, packages everything into
`InstallShir.zip`, and writes `InstallShir.zip.sha256` next to it. CI runs
the same script in the `terraform-validate` job and compares the SHA256 to
catch drift between the source and the artifact.

The compiled `.zip` is treated as a derived artifact: it is NOT committed to
the repo so each environment recompiles from source. CI re-runs the build
on every PR.

## Choosing an install method

| Method | When to use |
| --- | --- |
| `DSC` (default) | Always, unless an Azure Government egress policy blocks DSC pull from `wpr.azure.com`. Self-heals on auth-key rotation. |
| `CustomScript` | Sovereign-cloud fallback. Re-applies the install + register on every Terraform run; no drift detection. |

See [docs/ingestion/sql-managed-instance.md](../../../docs/ingestion/sql-managed-instance.md) for the operator runbook.

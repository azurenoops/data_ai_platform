# SQL Managed Instance

> [!WARNING]
> **Structured-data ACL caveat.** Rows ingested from SQL MI flow through the structured-data path (Parquet → Synapse views) and have **no per-row ACL filtering** at MCP query time. Any caller able to invoke a SQL-MI-backed tool sees every row in the view. See [Ingestion hub §5.1](../INGESTION.md#51-why-structured-queries-dont-enforce-securityids) for mitigation patterns.

> Operator cookbook for ingesting tables from a SQL Managed Instance into the structured-data path.
>
> See the [Ingestion hub](../INGESTION.md) for cross-cutting concepts.

## What this source provides

- One Parquet file per table per run, written under `raw/sqlmi/<schema>.<table>/`
- Promoted to `curated/sqlmi/...` by `CurationFunction`
- Surfaced via Synapse serverless views defined in [`infra/synapse/views/`](../../infra/synapse/views/)

## Architecture

```
SQL Managed Instance (private endpoint)
        │  AzureSqlMI linked service
        │  (Managed Identity auth — ADF UAMI)
        ▼
ADF pipeline pl_sql_mi_to_adls
        │  ForEach over tables[].schema/.name
        │  CopyActivity → Parquet
        ▼
        raw/sqlmi/<schema>.<table>/<run-id>.parquet
                │
                ▼ (event-grid .parquet)
            CurationFunction
                │
                ▼
        curated/sqlmi/<schema>.<table>/...
                │
                ▼
        Synapse serverless views
```

Pipeline JSON: [`infra/datafactory/pipelines/pl_sql_mi_to_adls.json`](../../infra/datafactory/pipelines/pl_sql_mi_to_adls.json)

## Required Azure resources & permissions

| Item | Required | Notes |
| --- | --- | --- |
| ADF MI granted `Storage Blob Data Contributor` on platform storage | Yes | Auto-granted |
| ADF MI as a SQL MI user with `db_datareader` on the source DB | **Yes — operator T-SQL step** | See step 2 below; cannot be done via Terraform |
| Connectivity from ADF to SQL MI | Yes | Either via the auto-resolve IR (public endpoint enabled on MI) or via SHIR (private-only MI) |
| Self-Hosted IR | Optional | Required when MI exposes only the private endpoint |

## Configuration

| Variable | Required | Example |
| --- | --- | --- |
| `enable_data_factory_pipelines` | Yes | `true` |
| `sql_mi_server_fqdn` | Yes | `phwc-sqlmi.public.<dnszone>.database.windows.net,3342` |
| `sql_mi_database` | Yes | `phwc_data` |
| `sql_mi_tables` | Yes | `[{schema="dbo", name="Cases"},{schema="dbo", name="Submissions"}]` |
| `sql_mi_schedule_cron` | No | `0 0 4 * * *` (daily 04:00 UTC, default) |
| `sql_mi_use_shir` | No | `false`; `true` for private-endpoint-only MI |

## Step-by-step onboarding

### 1. Identify the ADF UAMI

```bash
ADF_PRINCIPAL_ID=$(terraform -chdir=infra output -raw DATA_FACTORY_IDENTITY_PRINCIPAL_ID)
ADF_NAME=$(terraform -chdir=infra output -raw DATA_FACTORY_NAME)
echo "ADF UAMI principal ID: $ADF_PRINCIPAL_ID"
echo "ADF resource name: $ADF_NAME"
```

### 2. Grant the ADF UAMI database access on SQL MI

Connect to the MI as a user that can `CREATE USER` (typically the `sqladmin`):

```sql
USE [phwc_data];
GO

-- Create the AAD-backed user. Use the ADF resource NAME (not principal ID) since
-- AAD authentication for SQL MI binds by display name when the principal is a UAMI.
CREATE USER [adf-phwc-prod] FROM EXTERNAL PROVIDER;
GO

-- Read-only access on the user tables this pipeline will copy.
ALTER ROLE db_datareader ADD MEMBER [adf-phwc-prod];
GO
```

> Replace `adf-phwc-prod` with the actual `DATA_FACTORY_NAME` output. If you use a system-assigned identity instead, the display name is `<adf-name>` (no suffix).

### 3. Set the tfvars and apply

```hcl
# infra/envs/dev.tfvars
enable_data_factory_pipelines = true
enable_data_factory_schedules = true
sql_mi_server_fqdn = "phwc-sqlmi.public.abc123.database.windows.net,3342"
sql_mi_database    = "phwc_data"
sql_mi_tables = [
  { schema = "dbo", name = "Cases" },
  { schema = "dbo", name = "Submissions" },
]
```

```bash
terraform -chdir=infra apply -var-file=envs/dev.tfvars
```

### 4. (Private-endpoint-only MI) Enable SHIR routing

If the MI does not expose its public endpoint, you also need:

```hcl
enable_self_hosted_integration_runtime = true
sql_mi_use_shir                        = true
enable_shir_host_vm                    = true
shir_host_subnet_id                    = "/subscriptions/.../subnets/shir"
```

See the [SHIR section](#shir-fallback-and-dsc-vs-customscript) below.

### 5. Trigger and verify

```bash
RG=$(terraform -chdir=infra output -raw RESOURCE_GROUP_NAME)
ADF=$(terraform -chdir=infra output -raw DATA_FACTORY_NAME)
az datafactory pipeline create-run \
  --resource-group $RG --factory-name $ADF \
  --pipeline-name pl_sql_mi_to_adls
```

```bash
# Confirm Parquet files
az storage fs file list \
  --auth-mode login \
  --account-name <storage> --file-system raw \
  --path sqlmi --num-results 20 -o table
```

## SHIR fallback and DSC vs. CustomScript

The platform supports two SHIR install paths on the SHIR host VM:

| Method | Default? | When to use |
| --- | --- | --- |
| `DSC` | Yes | Standard commercial Azure deployments |
| `CustomScript` | No | Sovereign-cloud (Gov / IL5) where DSC pull endpoints (`wpr.azure.com`) are blocked by egress policies |

Set `shir_install_method = "CustomScript"` in your tfvars to use the fallback. The fallback script is at [`infra/modules/shirhost/scripts/install-shir.ps1`](../../infra/modules/shirhost/scripts/install-shir.ps1) and uses an `Invoke-WebRequest` + `msiexec /quiet` approach without DSC.

The DSC config source is at [`infra/modules/shirhost/dsc/InstallShir.ps1`](../../infra/modules/shirhost/dsc/InstallShir.ps1) and is compiled to `InstallShir.zip` via [`infra/modules/shirhost/dsc/build-dsc.ps1`](../../infra/modules/shirhost/dsc/build-dsc.ps1) (run by CI; output is uploaded to the `deploy/` filesystem).

After the host comes up, retrieve the auth key (sensitive output):

```bash
SHIR_KEY=$(terraform -chdir=infra output -raw self_hosted_integration_runtime_primary_key)
# Both methods consume this from the protected_settings of the extension; no manual paste needed.
```

If you need to manually re-register a SHIR node:

```powershell
& 'C:\Program Files\Microsoft Integration Runtime\5.0\Shared\dmgcmd.exe' -RegisterNewNode '<auth-key>'
```

## How to verify

```kusto
ADFPipelineRun
| where PipelineName == "pl_sql_mi_to_adls"
| project Start, Status, DurationInMs, FailureType, Error
| top 10 by Start desc
```

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Pipeline `Failed` with `Login failed for user '<token-identified>'` | ADF UAMI not added to the MI database | Re-run step 2 |
| `Cannot open server ... requested by the login` | MI public endpoint disabled or firewall blocking ADF outbound IPs | Enable SHIR (`sql_mi_use_shir=true`) |
| `EXECUTE permission was denied on the object 'sp_columns'` | UAMI is `db_datareader` but the table has additional schema-bind permissions | Grant `VIEW DEFINITION` or use `SELECT *` mode in the dataset |
| SHIR offline | Host VM rebooted, auth key rotated | RDP via bastion; check `Get-Service DIAHostService`; re-run DSC extension |

## Limits and scaling

- Single-row table copies bottleneck on connection pool. For tables > 100 M rows, partition the copy by primary-key range (override the pipeline JSON) or schedule per-table runs.
- The default cron (`0 0 4 * * *` = daily 04:00 UTC) is conservative; tighten if your MI has the throughput.

## Sovereign-cloud notes

- Use `database.usgovcloudapi.net` in `sql_mi_server_fqdn`.
- Use `shir_install_method = "CustomScript"` if the host VM cannot reach `wpr.azure.com`.

## See also

- [secret-rotation.md](secret-rotation.md) for SHIR host admin password rotation
- [`infra/modules/shirhost/`](../../infra/modules/shirhost/) source

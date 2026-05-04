# Dataverse (via Synapse Link)

> [!WARNING]
> **Structured-data ACL caveat.** Rows ingested from Dataverse flow through the structured-data path (Parquet → Synapse views) and have **no per-row ACL filtering** at MCP query time. Any caller able to invoke a Dataverse-backed tool sees every row in the view. See [Ingestion hub §5.1](../INGESTION.md#51-why-structured-queries-dont-enforce-securityids) for mitigation patterns.

> Operator cookbook for ingesting Dataverse tables via **Azure Synapse Link for Dataverse**. The link is wired in the Power Platform admin center; this platform consumes the resulting Parquet via Synapse serverless views.
>
> See the [Ingestion hub](../INGESTION.md) for cross-cutting concepts.

## What this source provides

- Continuous near-real-time replication of Dataverse tables to ADLS Gen2 in Parquet format
- Schema kept in sync with Dataverse via the Synapse Link delta-incremental option
- Surfaced via Synapse serverless views

## Architecture

```
Dataverse environment
      │  Synapse Link for Dataverse
      │  (configured in Power Platform admin center —
      │   NOT a Terraform resource)
      ▼
   curated/<dataverse_synapselink_path>/
      │  (Synapse Link writes here directly)
      ▼
   Synapse serverless views
```

> The platform's `pl_dataverse_via_synapselink` ADF pipeline is a **connectivity-marker** — it does **not** copy data. Its only job is to run a daily probe against the expected ADLS path so operators get an alert when Synapse Link is unconfigured or has drifted.

Pipeline JSON: [`infra/datafactory/pipelines/pl_dataverse_via_synapselink.json`](../../infra/datafactory/pipelines/pl_dataverse_via_synapselink.json)

## Required Azure resources & permissions

| Item | Required | Notes |
| --- | --- | --- |
| Dataverse environment with system-admin access | Yes | Operator only |
| Power Platform admin-center access | Yes | Operator only |
| ADLS Gen2 storage (the same one this platform uses) | Yes | Synapse Link writes to a folder under `curated/` |
| ADF MI granted Storage Blob Data Reader on platform storage | Yes | Auto-granted via [`infra/modules/roleassignments`](../../infra/modules/roleassignments) |

## Configuration

| Variable | Required | Example |
| --- | --- | --- |
| `enable_data_factory_pipelines` | Yes | `true` |
| `dataverse_synapselink_path` | No | `synapselink` (default) — the subpath under `curated/` where Synapse Link writes |
| `dataverse_schedule_cron` | No | `0 0 7 * * *` (daily 07:00 UTC, default) |
| `dataverse_probe_enabled` | No | `false` (default); `true` enables a Terraform-time `null_resource` post-deploy probe via `az storage fs file list` |

## Step-by-step onboarding

### 1. Identify the destination ADLS path

```bash
STORAGE=$(terraform -chdir=infra output -raw STORAGE_ACCOUNT_NAME)
PATH_SEG=$(terraform -chdir=infra output -raw DATAVERSE_SYNAPSELINK_PATH)   # default "synapselink"
echo "Destination: abfss://curated@${STORAGE}.dfs.core.windows.net/${PATH_SEG}"
```

### 2. Create the Synapse Link in Power Platform admin center

> This step **cannot be Terraform-automated**. The Synapse Link wizard is a Power Platform feature, not an Azure resource. Run as a Dataverse system-admin.

1. Open <https://admin.powerplatform.microsoft.com/> and select your environment.
2. Navigate to **Azure Synapse Link** (under **Data integration**).
3. Click **+ New Link**.
4. **Storage account**: select the platform's storage account (the value of `STORAGE` above). The wizard requires the operator account to have `Storage Blob Data Owner` on the account; this is **NOT** a permission the platform grants by default — request it from your Azure subscription admin for the duration of the wizard, then revoke.
5. **Container**: select `curated`.
6. **Folder path**: enter the value of `PATH_SEG` above (`synapselink` by default).
7. **Tables**: select the Dataverse tables you want replicated. The Synapse Link supports incremental refresh; choose **Append-only** unless you need physical deletes.
8. **Synapse workspace**: optional — only if you also want the Synapse-managed views auto-generated. Our platform has its own Synapse workspace; enabling this option here would create duplicate views. **Skip** unless you've checked this with the platform operator.
9. Submit and wait for the initial sync to complete (can take 30 min – 12 h depending on table sizes).

### 3. Verify the path is populated

After the initial sync:

```bash
az storage fs file list \
  --auth-mode login \
  --account-name $STORAGE --file-system curated \
  --path $PATH_SEG --num-results 5 -o table
```

You should see one folder per table (e.g., `account/`, `contact/`).

### 4. Set the tfvars and apply (deploys the marker pipeline + optional probe)

```hcl
# infra/envs/dev.tfvars
enable_data_factory_pipelines = true
enable_data_factory_schedules = true
dataverse_synapselink_path    = "synapselink"
dataverse_probe_enabled       = true   # enables the post-deploy az storage fs file list probe
```

```bash
terraform -chdir=infra apply -var-file=envs/dev.tfvars
```

> The `null_resource.synapselink_path_probe` runs at apply time and **fails** if the path is empty. This is the documented signal that step 2 hasn't completed yet — do step 2 first, then re-apply.

### 5. Confirm the Synapse views

The platform's Synapse views are defined in [`infra/synapse/views/`](../../infra/synapse/views/). Once Synapse Link is writing, the views auto-resolve their underlying Parquet.

## How to verify

```kusto
ADFPipelineRun
| where PipelineName == "pl_dataverse_via_synapselink"
| project Start, Status, DurationInMs
| top 10 by Start desc
```

The marker pipeline run takes ~5 seconds; failures indicate ADF lost connectivity to the storage account, which is independent of the Synapse Link health.

For Synapse Link health, check the Power Platform admin center → Azure Synapse Link → status panel.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Probe fails at `terraform apply` | Synapse Link not yet configured | Complete step 2; rerun apply |
| Probe fails after rotation | Synapse Link path changed in Power Platform admin center | Update `dataverse_synapselink_path` tfvar to match |
| Marker pipeline `Failed` | ADF MI lost Storage Blob Data Reader | Re-run `terraform apply`; the role assignment is in [`infra/modules/roleassignments/main.tf`](../../infra/modules/roleassignments/main.tf) |
| Synapse views return zero rows | Initial Synapse Link sync still running | Check admin-center status; wait |

## Limits and scaling

- Synapse Link's append-only mode keeps a delta change feed; query patterns over very high-velocity tables (>1M rows/day) should pre-aggregate via Synapse views rather than scanning the raw delta files.
- Dataverse imposes per-environment Synapse Link entity limits (typically 100 tables); see [Microsoft's Synapse Link limits](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/azure-synapse-link-data-lake) for current numbers.

## Sovereign-cloud notes

- For Gov-cloud, the Power Platform admin center and storage account must both be in the same sovereign region.
- The platform's storage URL convention assumes `core.windows.net`; for Gov override the connection-string template in [`infra/modules/datafactory/dataverse.tf`](../../infra/modules/datafactory/dataverse.tf) if it directly references the storage URL.

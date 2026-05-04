# Azure File Share

> Operator cookbook for ingesting binary files from a separate Azure File Share storage account into the platform via Azure Data Factory.
>
> See the [Ingestion hub](../INGESTION.md) for cross-cutting concepts.

## What this source provides

- Binary files (any format the platform's Document Intelligence layout can parse) on an Azure File Share
- A daily inventory Parquet at `raw/afs/inventory/` describing the share's contents (file name, size, last-modified)
- Same downstream RAG pipeline as SharePoint/OneDrive

## Architecture

```
External Azure File Share storage account
        │  AzureFileStorage linked service
        │  (account key from Key Vault)
        ▼
ADF pipeline pl_afs_to_adls
        ├─ Copy binaries     → landing/afs/<path>
        └─ Copy _inventory  → raw/afs/inventory/*.parquet
                │
                ▼
       (event-grid blob created on landing/)
                │
                ▼
         IngestBlobFunction
                │
                ▼
      DocumentIngestionPipeline → AI Search
```

Pipeline JSON: [`infra/datafactory/pipelines/pl_afs_to_adls.json`](../../infra/datafactory/pipelines/pl_afs_to_adls.json)

## Required Azure resources & permissions

| Item | Required | Notes |
| --- | --- | --- |
| ADF MI granted `Storage Blob Data Contributor` on **platform** storage account | Yes | Auto-granted |
| ADF MI granted `Key Vault Secrets User` on **platform** Key Vault | Yes (when `enable_data_factory_pipelines=true`) | Auto-granted by [`infra/modules/roleassignments`](../../infra/modules/roleassignments) |
| AFS storage account access key in **platform** Key Vault | **Yes — operator pre-creates** | Secret name `afs-storage-key` (configurable via `afs_storage_key_secret_name`) |
| Self-Hosted IR | Optional | Only if AFS account is firewall-restricted |

> **Why an account key, not MI?** ADF's `AzureFileStorage` linked service does not currently support managed-identity auth in all regions. Holding the key in our Key Vault keeps it out of state files and rotateable.

## Configuration

These are Terraform tfvars (set in [`infra/envs/dev.tfvars`](../../infra/envs/dev.tfvars) or via your CI):

| Variable | Required | Example |
| --- | --- | --- |
| `enable_data_factory_pipelines` | Yes | `true` |
| `afs_storage_account_name` | Yes | `phwccontoso` |
| `afs_share_name` | Yes | `documents` |
| `afs_storage_key_secret_name` | No | `afs-storage-key` (default) |
| `afs_schedule_cron` | No | `0 0 5 * * *` (daily 05:00 UTC, default) |
| `afs_use_shir` | No | `false` (default); `true` to route through SHIR |

## Step-by-step onboarding

### 1. Pre-create the AFS storage key secret in Key Vault

```bash
# Get the source storage account key
KEY=$(az storage account keys list \
  --resource-group <source-rg> --account-name phwccontoso \
  --query '[0].value' -o tsv)

# Set in our platform KV; expiry-monitored by the kv_secret_expiry alert
az keyvault secret set \
  --vault-name <platform-kv> \
  --name afs-storage-key \
  --value "$KEY" \
  --expires "$(date -u -v +90d '+%Y-%m-%dT%H:%M:%SZ')"   # macOS
  # Linux: --expires "$(date -u -d '+90 days' '+%Y-%m-%dT%H:%M:%SZ')"
```

> The 90-day expiry is intentional: the [secret-rotation cadence](secret-rotation.md) is 90 days for AFS keys, and the [`kv_secret_expiry`](../../infra/modules/alerts/main.tf) alert fires at T-30.

### 2. Create the `_inventory` listing on the share

The pipeline copies a CSV manifest from `_inventory/files.csv` on the share. Generate it nightly via your existing share-management workflow, or with a small script (run on a host that has the share mounted):

```powershell
Get-ChildItem -Path \\phwccontoso.file.core.windows.net\documents -Recurse -File |
  Select-Object FullName,Length,LastWriteTimeUtc |
  ConvertTo-Csv -NoTypeInformation |
  Out-File \\phwccontoso.file.core.windows.net\documents\_inventory\files.csv -Encoding utf8
```

### 3. Set the tfvars and apply

```hcl
# infra/envs/dev.tfvars
enable_data_factory_pipelines = true
enable_data_factory_schedules = true
afs_storage_account_name = "phwccontoso"
afs_share_name           = "documents"
```

```bash
terraform -chdir=infra apply -var-file=envs/dev.tfvars
```

### 4. Verify the deployment

```bash
# Linked service exists
terraform -chdir=infra output -raw DATA_FACTORY_LINKED_SERVICE_NAMES

# Trigger a manual pipeline run
ADF=$(terraform -chdir=infra output -raw DATA_FACTORY_NAME)
RG=$(terraform -chdir=infra output -raw RESOURCE_GROUP_NAME)
az datafactory pipeline create-run \
  --resource-group $RG --factory-name $ADF \
  --pipeline-name pl_afs_to_adls
```

## How to verify

```bash
# Confirm landing files
az storage fs file list \
  --auth-mode login \
  --account-name <storage> --file-system landing \
  --path afs --num-results 20 -o table

# Confirm inventory parquet
az storage fs file list \
  --auth-mode login \
  --account-name <storage> --file-system raw \
  --path afs/inventory --num-results 5 -o table

# Latest pipeline run status
az datafactory pipeline-run query-by-factory \
  --resource-group $RG --factory-name $ADF \
  --last-updated-after $(date -u -v -1d '+%Y-%m-%dT%H:%M:%SZ') \
  --last-updated-before $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
  --filters operand=PipelineName operator=Equals values=pl_afs_to_adls
```

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Pipeline `Failed`, error `KeyVaultSecretNotFound` | Secret missing or KV firewall blocking ADF | Verify secret name matches `afs_storage_key_secret_name`; confirm KV firewall allows the ADF subnet/private endpoint |
| Pipeline `Failed`, error `AuthorizationFailed` (storage) | Storage key rotated upstream; KV secret stale | Update KV secret per step 1 |
| Pipeline `Succeeded` but no files appear in `landing/afs/` | Source share path empty, or `_inventory` filter excluded everything | List the share manually with the same credentials |
| Pipeline times out on large shares | AFS read settings throttling | Set `afs_use_shir = true` and route through a SHIR host on the same VNet as the AFS account |

## Limits and scaling

- Default Azure IR throughput depends on the auto-resolve region. Cross-region copies add latency.
- For shares > 1 TB, schedule the pipeline weekly and use the inventory delta to drive incremental loads (out-of-the-box pipeline copies everything every run).

## Operations

- **Secret rotation cadence:** 90 days. See [secret-rotation.md](secret-rotation.md).

## Sovereign-cloud notes

The pipeline JSON uses `core.windows.net` in the connection-string template; for Gov-cloud override the connection-string template in [`infra/modules/datafactory/afs.tf`](../../infra/modules/datafactory/afs.tf) (replace `core.windows.net` with `core.usgovcloudapi.net`).

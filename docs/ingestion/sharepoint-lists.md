# SharePoint Lists

> [!WARNING]
> **Structured-data ACL caveat.** Rows ingested from SharePoint Lists flow through the structured-data path (Parquet → Synapse views) and have **no per-row ACL filtering** at MCP query time. Any caller able to invoke a list-backed tool sees every row in the view. See [Ingestion hub §5.1](../INGESTION.md#51-why-structured-queries-dont-enforce-securityids) for mitigation patterns.

> Operator cookbook for ingesting SharePoint Online **lists** (structured rows) — distinct from SharePoint **files** which are document libraries.
>
> See the [Ingestion hub](../INGESTION.md) for cross-cutting concepts.

## What this source provides

- One Parquet file per list per run, written under `raw/sharepoint-lists/<list>/`
- Schema is inferred from the list's column definitions
- Promoted to `curated/sharepoint-lists/...` and surfaced via Synapse views

> **Why an AAD app-reg, not the Function MI?** The ADF `SharePointOnlineList` connector requires an AAD application registration with delegated `Sites.Read.All`, not the application-permission `Sites.Read.All` we use for the file-ingestion Function. The two are administratively distinct in SharePoint Online.

## Architecture

```
SharePoint site
    └── List (e.g., "Cases", "Tickets")
            │  SharePointOnlineList linked service
            │  (AAD app-reg credentials in KV)
            ▼
    ADF pipeline pl_sharepoint_lists_to_adls
            │  ForEach over lists[]
            │  CopyActivity → Parquet
            ▼
       raw/sharepoint-lists/<list>/<run-id>.parquet
                │
                ▼ (event-grid .parquet)
            CurationFunction
                │
                ▼
       curated/sharepoint-lists/<list>/...
                │
                ▼
        Synapse serverless views
```

Pipeline JSON: [`infra/datafactory/pipelines/pl_sharepoint_lists_to_adls.json`](../../infra/datafactory/pipelines/pl_sharepoint_lists_to_adls.json)

## Required Azure resources & permissions

| Item | Required | Notes |
| --- | --- | --- |
| ADF MI granted `Storage Blob Data Contributor` on platform storage | Yes | Auto-granted |
| ADF MI granted `Key Vault Secrets User` on platform Key Vault | Yes | Auto-granted by [`infra/modules/roleassignments`](../../infra/modules/roleassignments) |
| AAD app-registration with delegated `Sites.Read.All` | **Yes — operator pre-creates** | See step 1 |
| App-reg client secret in platform Key Vault | **Yes — operator pre-creates** | Secret name `sharepoint-list-client-secret` (configurable) |

## Configuration

| Variable | Required | Example |
| --- | --- | --- |
| `enable_data_factory_pipelines` | Yes | `true` |
| `sharepoint_site_url` | Yes | `https://contoso.sharepoint.com/sites/cases` |
| `sharepoint_lists` | Yes | `["Cases", "Tickets"]` |
| `sharepoint_aad_app_tenant_id` | Yes | `<tenant-guid>` |
| `sharepoint_aad_app_client_id` | Yes | `<app-reg-client-guid>` |
| `sharepoint_aad_app_secret_name` | No | `sharepoint-list-client-secret` (default) |
| `sharepoint_schedule_cron` | No | `0 0 6 * * *` (daily 06:00 UTC, default) |
| `sharepoint_use_shir` | No | `false` |

## Step-by-step onboarding

### 1. Create the AAD app-registration

```bash
az ad app create --display-name "phwc-sharepoint-lists-adf" \
  --sign-in-audience AzureADMyOrg

APP_ID=$(az ad app list --display-name "phwc-sharepoint-lists-adf" --query '[0].appId' -o tsv)

# Add delegated Sites.Read.All (Microsoft Graph)
az ad app permission add \
  --id $APP_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 332a536c-c7ef-4017-ab91-336970924f0d=Scope

# Admin-consent the permission
az ad app permission admin-consent --id $APP_ID

# Create a service principal for the app
az ad sp create --id $APP_ID

# Generate a client secret (1-year expiry to align with rotation cadence)
SECRET=$(az ad app credential reset --id $APP_ID --years 1 --query password -o tsv)
echo "Client secret (store this in KV): $SECRET"
```

### 2. Grant the app-reg list-read access on the SharePoint site

The app-reg must be granted explicit access to the site collection. Run as a SharePoint admin (PowerShell, with `PnP.PowerShell` installed):

```powershell
Connect-PnPOnline -Url https://contoso.sharepoint.com/sites/cases -Interactive
Grant-PnPAzureADAppSitePermission -AppId <APP_ID> -DisplayName 'phwc-sharepoint-lists-adf' -Site (Get-PnPSite) -Permissions Read
```

### 3. Pre-create the secret in Key Vault

```bash
az keyvault secret set \
  --vault-name <platform-kv> \
  --name sharepoint-list-client-secret \
  --value "$SECRET" \
  --expires "$(date -u -v +90d '+%Y-%m-%dT%H:%M:%SZ')"   # 90-day rotation cadence
```

### 4. Set the tfvars and apply

```hcl
# infra/envs/dev.tfvars
enable_data_factory_pipelines = true
enable_data_factory_schedules = true

sharepoint_site_url          = "https://contoso.sharepoint.com/sites/cases"
sharepoint_lists             = ["Cases", "Tickets"]
sharepoint_aad_app_tenant_id = "<tenant-guid>"
sharepoint_aad_app_client_id = "<app-reg-client-guid>"
```

```bash
terraform -chdir=infra apply -var-file=envs/dev.tfvars
```

### 5. Trigger and verify

```bash
RG=$(terraform -chdir=infra output -raw RESOURCE_GROUP_NAME)
ADF=$(terraform -chdir=infra output -raw DATA_FACTORY_NAME)
az datafactory pipeline create-run \
  --resource-group $RG --factory-name $ADF \
  --pipeline-name pl_sharepoint_lists_to_adls
```

## How to verify

```bash
az storage fs file list \
  --auth-mode login \
  --account-name <storage> --file-system raw \
  --path sharepoint-lists --num-results 20 -o table
```

```kusto
ADFPipelineRun
| where PipelineName == "pl_sharepoint_lists_to_adls"
| project Start, Status, DurationInMs, Error
| top 10 by Start desc
```

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `Access denied` from SharePoint | Step 2 not done — app-reg has no site permission | Run `Grant-PnPAzureADAppSitePermission` |
| `KeyVaultSecretNotFound` | Secret name typo or KV firewall | Verify `sharepoint_aad_app_secret_name`; check KV firewall |
| `Invalid client secret` | Secret rotated upstream; KV out of date | Re-run step 3 with the new secret |
| Pipeline succeeds but list is empty | List title mismatch (case-sensitive in some configs) | Confirm exact list display name |

## Limits and scaling

- SharePoint Online throttles per app-reg at ~60,000 requests/hour.
- Each list copy is a single read; throughput is dominated by the list's row count.
- For lists > 100k items, schedule less frequently or paginate via custom pipeline overrides.

## Operations

- **Secret rotation cadence:** 90 days. See [secret-rotation.md](secret-rotation.md).

## Sovereign-cloud notes

- App-reg endpoint: use `https://login.microsoftonline.us` for Gov-cloud.
- Adjust `sharepoint_site_url` to use `*.sharepoint.us` if applicable.

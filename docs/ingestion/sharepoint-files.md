# SharePoint Files

> Operator cookbook for ingesting SharePoint Online document libraries via Microsoft Graph drives. ACL-trimmed; suitable for files with row-level access requirements.
>
> See the [Ingestion hub](../INGESTION.md) for cross-cutting concepts.

## What this source provides

- Binary documents stored in SharePoint Online document libraries (PDF, DOCX, XLSX, PPTX, etc.)
- Per-file ACL preservation: each file's drive-item permissions are resolved to AAD object IDs and written as `securityIds` blob metadata
- Full-text + semantic search through the AI Search `documents` index after ingestion

## Architecture

```
SharePoint site (Online)
    └── Document library (drive)
            │  Graph: GET /drives/{driveId}/root/children
            ▼
    SharePointFilesFunction (Timer, default every 30 min)
            │
            ├─ for each drive in SharePoint:DriveIds
            ├─ list items via GraphFileFetcher
            ├─ resolve per-item permissions → securityIds
            └─ download → upload to landing/sharepoint/<drive>/<path>
                                │
                                ▼
                       (event-grid blob created)
                                │
                                ▼
                        IngestBlobFunction
                                │
                                ▼
                     DocumentIngestionPipeline
                                │
                                ▼
                  AI Search documents index
```

Code:
- [`src/DataAiMcp.Ingestion.Functions/SharePointFilesFunction.cs`](../../src/DataAiMcp.Ingestion.Functions/SharePointFilesFunction.cs)
- [`src/DataAiMcp.Ingestion.Functions/Graph/GraphFileFetcher.cs`](../../src/DataAiMcp.Ingestion.Functions/Graph/GraphFileFetcher.cs)

## Required Azure resources & permissions

| Item | Required | Notes |
| --- | --- | --- |
| Functions app system-assigned MI granted Graph delegated-app permissions | Yes | `Sites.Read.All` + `Files.Read.All`; admin-consent required (see [`docs/DEPLOYMENT.md`](../DEPLOYMENT.md) Appendix B) |
| Storage Blob Data Contributor on the platform storage account | Yes | Auto-granted by `infra/modules/roleassignments` |
| Drive IDs of the document libraries | Yes | One-time lookup; see step 1 below |

## Configuration keys

| Key | Where set | Example |
| --- | --- | --- |
| `SharePoint__DriveIds` | Functions app settings | `["b!abc123...","b!def456..."]` |
| `SharePoint__Schedule` | Functions app settings | `0 */30 * * * *` (every 30 min) |
| `Graph__BaseUrl` | Functions app settings | `https://graph.microsoft.com/v1.0` (`.us` for Gov-cloud) |

## Step-by-step onboarding

### 1. Get admin consent for Graph permissions

If this is the first SharePoint/OneDrive source onboarded, follow [`docs/DEPLOYMENT.md`](../DEPLOYMENT.md) Appendix B to grant `Sites.Read.All` + `Files.Read.All` to the Functions app's MI. **One-time per environment.**

### 2. Resolve drive IDs for each document library

For each SharePoint site you want to ingest, list its drives:

```bash
SITE_HOSTNAME=tenant.sharepoint.com
SITE_PATH=/sites/<site-name>

# Resolve the site ID
SITE_ID=$(az rest --method GET \
  --url "https://graph.microsoft.com/v1.0/sites/${SITE_HOSTNAME}:${SITE_PATH}" \
  --query id -o tsv)

# List drives on the site
az rest --method GET \
  --url "https://graph.microsoft.com/v1.0/sites/${SITE_ID}/drives" \
  --query "value[].{name:name,id:id}" -o table
```

Copy the `id` of each drive you want to ingest.

### 3. Set the configuration

```bash
az functionapp config appsettings set \
  --name <funcapp> --resource-group <rg> \
  --settings \
    'SharePoint__DriveIds=["b!abc...","b!def..."]' \
    'SharePoint__Schedule=0 */30 * * * *'
```

### 4. Trigger or wait for the next run

The timer will pick up the new drives within 30 minutes (default). To trigger immediately, restart the Functions app.

## How to verify

```bash
# Confirm blobs are landing
az storage fs file list \
  --auth-mode login \
  --account-name <storage> --file-system landing \
  --path sharepoint --num-results 20 -o table

# Search hit on a known phrase
curl -X POST "https://<search>.search.windows.net/indexes/documents/docs/search?api-version=2024-07-01" \
  -H "Authorization: Bearer $(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv)" \
  -H "Content-Type: application/json" \
  -d '{"search":"<known phrase>","filter":"source eq '\''sharepoint'\''","top":3}'
```

App Insights KQL:

```kusto
dependencies
| where customDimensions.["service.namespace"] == "DataAiMcp"
| where customDimensions.source == "sharepoint"
| project timestamp, name, success, customDimensions.driveId, customDimensions.itemId
| top 50 by timestamp desc
```

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Function logs `403` from Graph | Admin consent not granted | Re-run [`docs/DEPLOYMENT.md`](../DEPLOYMENT.md) Appendix B |
| Function logs `429` from Graph | Per-tenant throttle | Increase `SharePoint__Schedule` interval or split drives across multiple Function instances |
| Blob lands but no search hit | `securityIds` empty (fail-closed) | Check Graph permission resolution — `customDimensions.securityIds == "[]"` in App Insights |
| Drive disappears | Drive renamed in SharePoint | Drive ID is stable across renames; verify the drive still exists via the lookup in step 2 |

## Limits and scaling

- Graph allows ~10,000 requests/sec/tenant; the function's default schedule keeps each drive's listing well under this.
- Each blob upload is a separate Graph download + Azure Storage write; large drives (>10k files) take longer than the schedule interval. The next run resumes naturally because the function is stateless and listings are sorted.
- For very large libraries, consider partitioning into multiple drives or scaling out to a Premium Functions plan.

## Sovereign-cloud notes

Set `Graph__BaseUrl=https://graph.microsoft.us/v1.0` for Gov-cloud. See [`docs/DEPLOYMENT.md`](../DEPLOYMENT.md) Appendix C.

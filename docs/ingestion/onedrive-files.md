# OneDrive Files

> Operator cookbook for ingesting per-user OneDrive content via Microsoft Graph drives. ACL-trimmed; **opt-in for ATO reasons**.
>
> See the [Ingestion hub](../INGESTION.md) for cross-cutting concepts.

## What this source provides

- Binary documents stored in users' personal OneDrive accounts
- Per-file ACL preservation via Graph drive-item permissions
- Same downstream pipeline as SharePoint files — chunks land in the AI Search `documents` index with `source = "onedrive"`

> **Why this is opt-in.** Personal OneDrive content can include drafts, performance reviews, and other sensitive material. Per-user ingestion expands the platform's data surface significantly and should be reviewed against your ATO data-handling boundary before enabling.

## Architecture

```
User OneDrive (Online)
    └── Personal drive
            │  Graph: GET /users/{upn}/drive
            ▼
    OneDriveFilesFunction (Timer, default every 6 hours)
            │
            ├─ for each drive in OneDrive:DriveIds
            ├─ list items via GraphFileFetcher
            ├─ resolve per-item permissions → securityIds
            └─ download → upload to landing/onedrive/<drive>/<path>
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
- [`src/DataAiMcp.Ingestion.Functions/OneDriveFilesFunction.cs`](../../src/DataAiMcp.Ingestion.Functions/OneDriveFilesFunction.cs)
- [`src/DataAiMcp.Ingestion.Functions/Graph/GraphFileFetcher.cs`](../../src/DataAiMcp.Ingestion.Functions/Graph/GraphFileFetcher.cs)

## Required Azure resources & permissions

| Item | Required | Notes |
| --- | --- | --- |
| Functions app MI granted `Files.Read.All` (Graph) | Yes | Admin-consent required; same flow as SharePoint files |
| Storage Blob Data Contributor on the platform storage account | Yes | Auto-granted |
| Drive IDs of the users to ingest | Yes | One-time lookup per user |

## Configuration keys

| Key | Where set | Example |
| --- | --- | --- |
| `OneDrive__DriveIds` | Functions app settings | `["b!user1...","b!user2..."]` |
| `OneDrive__Schedule` | Functions app settings | `0 0 */6 * * *` (every 6 hours) |
| `Graph__BaseUrl` | Functions app settings | `https://graph.microsoft.com/v1.0` (`.us` for Gov-cloud) |

## Step-by-step onboarding

### 1. Get admin consent (once per environment)

See [`docs/DEPLOYMENT.md`](../DEPLOYMENT.md) Appendix B. The same `Files.Read.All` consent that covers SharePoint files also covers OneDrive.

### 2. Resolve drive IDs

```bash
USER_UPN=alice@contoso.com
az rest --method GET \
  --url "https://graph.microsoft.com/v1.0/users/${USER_UPN}/drive" \
  --query id -o tsv
```

Repeat for each user. Driver IDs are stable across renames and are tied to the user's OneDrive site collection.

### 3. Set the configuration

```bash
az functionapp config appsettings set \
  --name <funcapp> --resource-group <rg> \
  --settings \
    'OneDrive__DriveIds=["b!user1...","b!user2..."]' \
    'OneDrive__Schedule=0 0 */6 * * *'
```

### 4. Trigger or wait for the next run

Default cadence is **6 hours** (vs. 30 min for SharePoint) because OneDrive volume is typically much larger and per-user files change less frequently.

## How to verify

```bash
az storage fs file list \
  --auth-mode login \
  --account-name <storage> --file-system landing \
  --path onedrive --num-results 20 -o table
```

```kusto
dependencies
| where customDimensions.source == "onedrive"
| project timestamp, name, success, customDimensions.driveId
| top 50 by timestamp desc
```

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Function logs `403` from Graph | Admin consent not granted, or user's tenant blocks app-only access to OneDrive | Verify admin consent; check Conditional Access policies |
| Function logs `404` for a drive | User offboarded; drive deleted | Remove the drive ID from `OneDrive__DriveIds` |
| Function takes a very long time per run | Default `OneDrive__Schedule` is 6h; one user has tens of thousands of files | Use Premium plan or split users across multiple Function apps |
| Blob lands but no search hit | `securityIds` empty (fail-closed) | Check user's tenant permissions on the file |

## Limits and scaling

- Graph throttles per user-drive at ~600 requests/min. Listing > 10k items will exceed this; the function honors retry-after headers but may take multiple runs to complete.
- Embedding throughput becomes the bottleneck for high-velocity drives — see the [Ingestion hub §9](../INGESTION.md) for the embedding-throttle alert.

## Sovereign-cloud notes

Same as SharePoint Files; set `Graph__BaseUrl=https://graph.microsoft.us/v1.0` for Gov-cloud.

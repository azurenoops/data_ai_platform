# Manual blob drop

> Operator cookbook for ad-hoc ingestion: upload a file directly to `landing/` and let the platform's Document RAG pipeline pick it up.
>
> See the [Ingestion hub](../INGESTION.md) for cross-cutting concepts.

## When to use this path

- One-off ingestion of a small set of documents (e.g., a single PDF for testing)
- Sources that aren't covered by an existing connector and don't justify a new Function or ADF pipeline yet
- Demos / dev-loop validation

If you find yourself doing this regularly for the same source type, build a proper connector instead — see [adding-a-source-type.md](adding-a-source-type.md).

## Architecture

```
Operator workstation
        │  az storage fs file upload (RBAC auth)
        ▼
    landing/<source>/<path>
        │  (event-grid blob created)
        ▼
   IngestBlobFunction
        │
        ▼
DocumentIngestionPipeline → AI Search
```

Code: [`src/DataAiMcp.Ingestion.Functions/IngestBlobFunction.cs`](../../src/DataAiMcp.Ingestion.Functions/IngestBlobFunction.cs)

## Required permissions

The operator's identity (user or service principal) needs `Storage Blob Data Contributor` on the platform's storage account. The platform's CI / Terraform deployer typically already has this.

## Configuration keys

There is **no** configuration for this path — it inherits whatever is wired for the Document RAG path generally. The only operator-tunable surface is the `securityIds` blob metadata you set per file (see below).

## Step-by-step

### 1. (Optional) Pick a source name

The `<source>/` prefix under `landing/` becomes the `documents.source` field on every chunk produced from your file. Reuse an existing source name if you're augmenting it; otherwise pick something memorable like `manual` or `adhoc-2024-q4`.

### 2. Decide on the ACL

| Audience | `securityIds` value |
| --- | --- |
| Tenant-wide (default) | `["__org__"]` (or omit; this is the implicit fallback) |
| Truly public — no caller required | `["__everyone__"]` (use rarely; bypasses MCP filtering) |
| Specific AAD groups / users | `["<group-object-id-1>", "<user-object-id-2>", ...]` |

> See [Ingestion hub §5](../INGESTION.md#5-acl-trimming-model) for what these IDs mean.

### 3. Upload with the chosen metadata

```bash
# Tenant-wide (default; no metadata needed)
az storage fs file upload \
  --auth-mode login \
  --account-name <storage> --file-system landing \
  --source ./mydoc.pdf --path manual/mydoc.pdf \
  --overwrite

# With a specific group ID
az storage fs file upload \
  --auth-mode login \
  --account-name <storage> --file-system landing \
  --source ./restricted.pdf --path manual/restricted.pdf \
  --overwrite

az storage blob metadata update \
  --auth-mode login \
  --account-name <storage> --container-name landing \
  --name manual/restricted.pdf \
  --metadata securityIds='["<group-object-id>"]'
```

> Why two commands for the metadata case? The DataLake `file upload` command does not accept arbitrary metadata; the Blob `metadata update` does. The platform reads the metadata from the blob namespace.

### 4. Verify ingestion

Wait ~30 seconds for the event-grid trigger, then:

```kusto
dependencies
| where customDimensions.source == "manual"
| where name contains "DocumentIngestionPipeline"
| top 5 by timestamp desc
```

```bash
# Search hit
curl -X POST "https://<search>.search.windows.net/indexes/documents/docs/search?api-version=2024-07-01" \
  -H "Authorization: Bearer $(az account get-access-token --resource https://search.azure.com --query accessToken -o tsv)" \
  -H "Content-Type: application/json" \
  -d '{"search":"<phrase from your doc>","filter":"source eq '\''manual'\''","top":3}'
```

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Upload succeeds but no search hit | Event-grid subscription on `landing/` removed | `az eventgrid system-topic event-subscription list -g <rg>` |
| Function logs `Document Intelligence` 4xx | File format unsupported | DI supports PDF, DOCX, XLSX, PPTX, HTML, MD, TXT, image formats; see DI docs |
| Search returns the file but with empty `securityIds` | Metadata not propagated (race between upload and read) | Re-upload after a short delay; the function reads metadata at trigger time |
| Search filters on caller IDs hide the document | The blob's `securityIds` doesn't include any of the caller's IDs | Inspect the blob's metadata; broaden if appropriate |

## Limits and scaling

- Single-file uploads scale fine to ~tens of files per minute. For larger volumes use a real connector.
- The `IngestBlobFunction` will queue uploads behind whatever embedding deployment quota is available; large bursts may take time to drain (visible in the [embedding-throttle](../../infra/modules/alerts/main.tf) alert).

## Sovereign-cloud notes

No special handling — same `az storage fs file upload` works against `*.dfs.core.usgovcloudapi.net` storage accounts.

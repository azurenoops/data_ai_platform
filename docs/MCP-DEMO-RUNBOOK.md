# MCP Demo Runbook (Central US)

This runbook covers:
1. What demo data was created
2. How data was ingested
3. How to connect to MCP
4. Demo prompts that show meaningful output
5. Troubleshooting checkpoints

## 1) Demo data created

### Document-style content (RAG / unstructured)
Uploaded to `landing/manual/`:
- `fleet_ops_quarterly_report.docx`
- `incident_lessons_learned.docx`
- `program_portfolio_kpis.xlsx`
- `mission_events_analytics.xlsx`

These files include:
- Multi-section operational narratives
- Incident summaries and corrective actions
- Program KPI and supplier workbook tabs
- Mission event records with status/region/system dimensions

### SQL demo exports (RAG via spreadsheet documents)
The SQL tables are surfaced to RAG as `.xlsx` workbooks (source `sql-demo`).
Raw `.csv` is **not** parsed by Document Intelligence layout, so the CSV exports in
`demo-data/sql/exports/` are converted to compact `.xlsx` by
`demo-data/convert_sql_exports_to_xlsx.py` and uploaded to `landing/sql-demo/`:
- `customers.xlsx` (300 rows)
- `projects.xlsx` (1200 rows)
- `workorders.xlsx` (sampled to 800 rows)
- `inspection_findings.xlsx` (sampled to 800 rows)
- `telemetry_readings.xlsx` (sampled to 800 rows)

The large tables are **sampled** for the RAG/document path to keep each workbook
small enough to ingest within the Functions HTTP timeout and embedding budget.
Exhaustive, exact analytics over the full tables are served by the structured
`query_structured_data` tool (section C2), not the document path.

### Azure SQL database (structured source for downstream ingestion)
Provisioned:
- SQL server: `sqlmcpdemo04753339edf2b.database.windows.net`
- Database: `mcpdemo`

Populated tables and row counts:
- `dbo.Customers`: 300
- `dbo.Projects`: 1200
- `dbo.WorkOrders`: 5000
- `dbo.InspectionFindings`: 9000
- `dbo.TelemetryReadings`: 20000

## 2) Ingestion status and flow

Two distinct paths feed the demo:

**Document path (RAG)** — unstructured + tabular `.xlsx`:
- Files are uploaded to the ADLS Gen2 `landing/` filesystem.
- Ingestion is invoked through the `IngestBlobHttp` webhook (Event-Grid-shaped
  array body), which runs the document pipeline and writes AI Search chunks.
- `manual/*` docs land as source `manual`; `sql-demo/*.xlsx` land as source `sql-demo`
  (the source name is the first path segment of the blob name).

Verification command for staged files:
```bash
STORAGE=$(terraform -chdir=infra output -raw STORAGE_ACCOUNT_NAME)
az storage fs file list --auth-mode login --account-name "$STORAGE" --file-system landing --path manual --num-results 50 -o table
az storage fs file list --auth-mode login --account-name "$STORAGE" --file-system landing --path sql-demo --num-results 50 -o table
```

Convert the CSV exports to compact `.xlsx` and upload them to `landing/sql-demo/`:
```bash
ST=$(terraform -chdir=infra output -raw STORAGE_ACCOUNT_NAME)
python3 -m pip install --quiet openpyxl
python3 demo-data/convert_sql_exports_to_xlsx.py
for f in customers projects workorders inspection_findings telemetry_readings; do
  az storage fs file upload --auth-mode login --account-name "$ST" --file-system landing \
    --source "demo-data/landing/sql-demo/$f.xlsx" --path "sql-demo/$f.xlsx" --overwrite -o none
done
```

Trigger document ingestion for the sql-demo workbooks (run after upload):
```bash
FUNC=func-ing-04753339edf2b
ST=$(terraform -chdir=infra output -raw STORAGE_ACCOUNT_NAME)
KEY=$(az functionapp function keys list -g rg-dataai-centralus -n "$FUNC" --function-name IngestBlobHttp --query default -o tsv)
for f in customers projects workorders inspection_findings telemetry_readings; do
  curl -s -m 280 -o /dev/null -w "$f http=%{http_code} time=%{time_total}s\n" \
    -X POST -H 'Content-Type: application/json' \
    -d '[{"data":{"url":"https://'$ST'.blob.core.windows.net/landing/sql-demo/'$f'.xlsx"}}]' \
    "https://$FUNC.azurewebsites.net/api/IngestBlobHttp?code=$KEY"
done
```

**Structured path (Synapse serverless)** — full tables for `query_structured_data`:
- Data Factory pipeline `pl_sql_mi_to_adls` copies each table to Parquet under the
  storage `raw` filesystem at `raw/sqlmi/<Table>/` (NOT `curated/`).
- Synapse serverless database **`datalake`** exposes one view per table over those
  Parquet files: `vw_sqlmi_customers`, `vw_sqlmi_projects`, `vw_sqlmi_workorders`,
  `vw_sqlmi_inspectionfindings`, `vw_sqlmi_telemetryreadings` (definitions in
  `infra/synapse/views/`). The MCP server queries these via app setting
  `Synapse__Database=datalake` using its managed identity.
- NOTE: if ADF is run multiple times it **appends** full-copy Parquet files, which
  multiplies row counts. Keep exactly one Parquet file per `raw/sqlmi/<Table>/`
  folder. Verified counts: Customers 300 / Projects 1200 / WorkOrders 5000 /
  InspectionFindings 9000 / TelemetryReadings 20000.

Legacy Parquet ingestion reference:
- Data Factory pipeline: `pl_sql_mi_to_adls`
- Source: `sqlmcpdemo04753339edf2b.database.windows.net,1433` / `mcpdemo`
- Tables copied: `Customers`, `Projects`, `WorkOrders`, `InspectionFindings`, `TelemetryReadings`

Verification (pipeline-level):
```bash
az datafactory pipeline-run show \
  --resource-group rg-dataai-centralus \
  --factory-name adf-04753339edf2b \
  --run-id 179b91d8-6a71-11f1-8f59-8aa245345769 \
  --query "{runId:runId,status:status,message:message}" -o json
```

Verification (activity-level row copies):
```bash
az datafactory activity-run query-by-pipeline-run \
  --resource-group rg-dataai-centralus \
  --factory-name adf-04753339edf2b \
  --run-id 179b91d8-6a71-11f1-8f59-8aa245345769 \
  --last-updated-after "$(date -u -v-2H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --last-updated-before "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --query "value[?activityName=='CopyTable'].{status:status,rowsCopied:output.rowsCopied,filesWritten:output.filesWritten}" -o table
```

One-command rerun + summary (recommended):
```bash
./demo-data/run-sql-demo-pipeline.sh
```

Script location:
- `demo-data/run-sql-demo-pipeline.sh`

## 3) Connect to MCP

Base URL:
- `https://app-mcp-04753339edf2b.azurewebsites.net`

MCP endpoint:
- `https://app-mcp-04753339edf2b.azurewebsites.net/mcp`

Acquire token. The MCP app registration (`api://f18f5d41-d7ff-4740-99c7-81f7d84edefd`)
exposes the API scope `access_as_user` and pre-authorizes the Azure CLI and VS Code
client IDs, so a user token can be minted directly:
```bash
AUD=$(az webapp config appsettings list -g rg-dataai-centralus -n app-mcp-04753339edf2b --query "[?name=='Auth__Audience'].value | [0]" -o tsv)
az account get-access-token --resource "$AUD" --query accessToken -o tsv
```

The token must have `aud` = the configured `Auth__Audience` and `scp` = `access_as_user`.
If token acquisition fails with `AADSTS650057`/`AADSTS65001` ("List of valid resources
from app registration" empty), the API scope or pre-authorized client is missing on the
app registration — re-add the `access_as_user` scope and pre-authorize the client app IDs
(Azure CLI `04b07795-8ddb-461a-bbee-02f9e1bf7b46`, VS Code `aebc6443-996d-45c2-90f0-388ff96faa56`)
in two separate Graph PATCHes (scope first, then `preAuthorizedApplications`).

Live audience/tenant check:
```bash
az webapp config appsettings list \
  -g rg-dataai-centralus \
  -n app-mcp-04753339edf2b \
  --query "[?name=='Auth__Audience' || name=='Auth__TenantId'].{name:name,value:value}" -o table
```

If token acquisition fails with `AADSTS500011`:
```bash
# 1) Ensure you're logged into the expected tenant
az logout
az login --tenant "f465eb03-88ee-4389-980b-48e355eb8fda"

# 2) Acquire token using the exact audience configured in Auth__Audience
AUD=$(az webapp config appsettings list -g rg-dataai-centralus -n app-mcp-04753339edf2b --query "[?name=='Auth__Audience'].value | [0]" -o tsv)
az account get-access-token --resource "$AUD" --query accessToken -o tsv
```

## 4) Demo prompts for MCP clients

Use these prompts in your MCP-enabled client after connecting.

### A) Quick capability check
- "List all available tools and briefly describe each one."
- "List available sources and top-level categories in the indexed corpus."

### B) Document intelligence showcase
- "From the fleet operations quarterly report, summarize readiness improvements and the top recurring fault families."
- "Find incidents mentioning config drift or expired credentials and summarize root causes and corrective actions."
- "What mission event patterns are visible by region and status in the mission analytics workbook?"
- "From the portfolio KPI workbook, identify programs with high burn rate and high risk level."

### C) SQL-style dataset insights (from ingested sql-demo .xlsx docs)
These run over the RAG document path (source `sql-demo`); answers reflect the
sampled workbooks. For exact/exhaustive numbers use the C2 structured prompts.
- "From the sql-demo project data, identify projects that are over budget and grouped by region or sector."
- "Summarize work orders by severity and system area, and highlight where hours-open are highest."
- "What finding types fail most often in inspection_findings? Include counts and likely hotspots."
- "Show telemetry trends for warning/critical health states and call out suspicious metrics."

### C2) Structured SQL dataset prompts (after `pl_sql_mi_to_adls`)
- "Using the structured SQL dataset, summarize row counts by table and highlight the largest table."
- "Which projects appear over budget (SpentUsd > BudgetUsd), and what patterns do you see by status?"
- "From WorkOrders and InspectionFindings, list the top severity/system-area combinations with the highest open workload."
- "From TelemetryReadings, identify metrics with frequent critical health state and propose monitoring thresholds."

### D) Cross-source synthesis
- "Correlate mission event anomalies with incident root causes and list plausible risk drivers."
- "Using portfolio, incident, and sql-demo records, propose a 30-day stabilization plan with priorities."

### E) Executive brief prompts
- "Create a one-page executive summary of operational risk, budget pressure, and supplier performance."
- "Give me top 10 actionable findings with owner/team suggestions and expected impact."

## 5) Troubleshooting

### If MCP returns 401/403
- Confirm the token `aud` matches `Auth__Audience` and `scp` includes `access_as_user`.
- Confirm the app registration still exposes the `access_as_user` scope and pre-authorizes
  your client app ID (see section 3).
- Confirm token tenant matches `Auth__TenantId`.
- Test health endpoint:
```bash
BASE=$(terraform -chdir=infra output -raw MCP_SERVER_BASE_URL)
curl -i "$BASE/healthz"
```

### If structured prompts (C2) return errors or no rows
- Confirm `Synapse__Database=datalake` on the MCP app settings (NOT `master`).
- Confirm the `vw_sqlmi_*` views exist in the `datalake` database and the MCP managed
  identity (`id-mcp-04753339edf2b`) has a database user with `db_datareader` and
  `ADMINISTER DATABASE BULK OPERATIONS`.
- Confirm exactly one Parquet file exists per `raw/sqlmi/<Table>/` folder (duplicates
  inflate counts).

### If search returns zero results for new docs
- Re-invoke the `IngestBlobHttp` webhook for the file (see section 2); wait for it to
  return HTTP 200, then allow a few seconds for indexing.
- Check function logs:
```bash
RG=$(terraform -chdir=infra output -raw AZURE_RESOURCE_GROUP)
FUNC=$(terraform -chdir=infra output -raw FUNCTION_APP_NAME)
az functionapp log tail -g "$RG" -n "$FUNC"
```

### If SQL pipeline path fails
- Validate linked service type and auth mode for Azure SQL DB vs SQL MI.
- Ensure firewall and Entra principal permissions are in place.

For this environment, these identity/permission checks were required:
- Data Factory system-assigned identity and user-assigned identity were granted `Storage Blob Data Contributor` on the storage account.
- Azure SQL users were created from external provider for:
  - `adf-04753339edf2b`
  - `id-adf-04753339edf2b`
- Both users were added to `db_datareader` in `mcpdemo`.

## 6) Demo sequence script (what to show live)

1. Show `/healthz` is green.
2. Ask MCP to list tools and sources.
3. Run 2-3 document prompts (readiness, incidents, mission analytics).
4. Run 2-3 sql-demo prompts (over-budget projects, severe work orders, telemetry risk).
5. Run one cross-source executive prompt.
6. Close with "top actions for next 30 days" prompt.

This sequence consistently demonstrates breadth (multiple data types), depth (specific evidence), and practical output (actionable recommendations).

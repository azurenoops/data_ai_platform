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

### SQL demo exports (RAG via CSV documents)
Uploaded to `landing/sql-demo/`:
- `customers.csv`
- `projects.csv`
- `workorders.csv`
- `inspection_findings.csv`
- `telemetry_readings.csv`

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

Current ingestion path used for the demo:
- Uploaded files to ADLS Gen2 `landing/` filesystem.
- `IngestBlobFunction` + document pipeline should process those files into AI Search chunks.

Verification command for staged files:
```bash
STORAGE=$(terraform -chdir=infra output -raw STORAGE_ACCOUNT_NAME)
az storage fs file list --auth-mode login --account-name "$STORAGE" --file-system landing --path manual --num-results 50 -o table
az storage fs file list --auth-mode login --account-name "$STORAGE" --file-system landing --path sql-demo --num-results 50 -o table
```

Structured SQL ingestion (Parquet path) has been executed for this demo:
- Data Factory pipeline: `pl_sql_mi_to_adls`
- Source: `sqlmcpdemo04753339edf2b.database.windows.net,1433` / `mcpdemo`
- Tables copied: `Customers`, `Projects`, `WorkOrders`, `InspectionFindings`, `TelemetryReadings`
- Final run status: `Succeeded`

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

Acquire token (audience currently configured per app registration strategy):
```bash
APP=$(terraform -chdir=infra output -raw APP_SERVICE_NAME)
az account get-access-token --resource "api://$APP" --query accessToken -o tsv
```

If that audience is not registered in Entra, use your configured custom audience value instead.

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

### C) SQL-style dataset insights (from ingested CSV docs)
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
- Confirm App Service public access is enabled.
- Confirm token audience and tenant match the MCP server auth settings.
- Test health endpoint:
```bash
BASE=$(terraform -chdir=infra output -raw MCP_SERVER_BASE_URL)
curl -i "$BASE/healthz"
```

### If search returns zero results for new docs
- Wait for blob-trigger ingestion to complete.
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

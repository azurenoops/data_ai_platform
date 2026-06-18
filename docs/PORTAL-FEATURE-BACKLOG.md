# Portal Feature Backlog

This backlog maps portal features directly to existing platform components so customers can self-serve onboarding, operations, and troubleshooting.

## Priority 1: Customer self-service foundation

### 1) Source Catalog and Data Dictionary

Why:
- Customers need to know what data exists before asking MCP questions.

Use existing components:
- MCP tool list and source metadata in [src/DataAiMcp.McpServer/Tools/MetadataTools.cs](../src/DataAiMcp.McpServer/Tools/MetadataTools.cs)
- Dataset schema metadata in [src/DataAiMcp.McpServer/Tools/StructuredTools.cs](../src/DataAiMcp.McpServer/Tools/StructuredTools.cs)
- Default catalog config in [src/DataAiMcp.McpServer/appsettings.json](../src/DataAiMcp.McpServer/appsettings.json)

Portal capability:
- List all configured sources, dataset names, columns, and sample questions
- Show a customer-friendly "what can I ask" panel per dataset

### 2) MCP Playground (no-code prompt test)

Why:
- Customers need to validate prompts without using CLI or a separate MCP client.

Use existing components:
- Tool contract surface in [src/DataAiMcp.McpServer/Tools/SearchTools.cs](../src/DataAiMcp.McpServer/Tools/SearchTools.cs)
- Structured query surface in [src/DataAiMcp.McpServer/Tools/StructuredTools.cs](../src/DataAiMcp.McpServer/Tools/StructuredTools.cs)
- Sample calling pattern in [src/Samples/DataAiMcp.SampleClient.Console/Program.cs](../src/Samples/DataAiMcp.SampleClient.Console/Program.cs)

Portal capability:
- Prompt runner for search_documents, get_document, list_sources, describe_dataset, query_structured_data
- Display generated SQL and row count for structured queries
- Save and share prompt templates

### 3) Source Onboarding Wizard

Why:
- The biggest customer pain is setup complexity for SharePoint, OneDrive, SQL MI, Dataverse, and blob-drop.

Use existing components:
- Source-specific playbooks in [docs/INGESTION.md](INGESTION.md)
- Detailed guides in [docs/ingestion/sharepoint-files.md](ingestion/sharepoint-files.md), [docs/ingestion/onedrive-files.md](ingestion/onedrive-files.md), [docs/ingestion/sql-managed-instance.md](ingestion/sql-managed-instance.md), [docs/ingestion/dataverse.md](ingestion/dataverse.md), [docs/ingestion/blob-drop.md](ingestion/blob-drop.md)
- Function schedules and source settings in [src/DataAiMcp.Ingestion.Functions/local.settings.template.json](../src/DataAiMcp.Ingestion.Functions/local.settings.template.json)

Portal capability:
- Guided forms for source setup inputs (drive IDs, schedules, pipeline names, landing paths)
- Validation checks before enabling a source
- "Copy command" helpers for any remaining manual steps

## Priority 2: Day-2 operations and trust

### 4) Ingestion Run Center

Why:
- Customers need one place to answer: Did my files ingest? What failed? What should I do next?

Use existing components:
- Blob ingest trigger in [src/DataAiMcp.Ingestion.Functions/IngestBlobFunction.cs](../src/DataAiMcp.Ingestion.Functions/IngestBlobFunction.cs)
- Dispatcher orchestration in [src/DataAiMcp.Ingestion.Functions/DispatcherFunction.cs](../src/DataAiMcp.Ingestion.Functions/DispatcherFunction.cs) and Graph ACL extraction in [src/DataAiMcp.Ingestion.Functions/Graph/GraphFileFetcher.cs](../src/DataAiMcp.Ingestion.Functions/Graph/GraphFileFetcher.cs)
- Structured curation stage in [src/DataAiMcp.Ingestion.Functions/CurationFunction.cs](../src/DataAiMcp.Ingestion.Functions/CurationFunction.cs)
- Existing SQL pipeline runner script in [demo-data/run-sql-demo-pipeline.sh](../demo-data/run-sql-demo-pipeline.sh)

Portal capability:
- Unified status board for source pulls, blob ingests, curation, and ADF runs
- Re-run buttons: reingest file, rerun source sync, rerun SQL pipeline
- Last-success and last-failure timestamps per source

### 5) ACL and Access Visibility

Why:
- Customers need confidence that document access is filtered correctly.

Use existing components:
- ACL extraction logic in [src/DataAiMcp.Ingestion.Functions/Graph/GraphFileFetcher.cs](../src/DataAiMcp.Ingestion.Functions/Graph/GraphFileFetcher.cs)
- Caller context and trimming model in [src/DataAiMcp.McpServer/Auth/CallerSecurityContext.cs](../src/DataAiMcp.McpServer/Auth/CallerSecurityContext.cs)
- Pipeline ACL fallback behavior in [src/DataAiMcp.Ingestion.Functions/Pipeline/DocumentIngestionPipeline.cs](../src/DataAiMcp.Ingestion.Functions/Pipeline/DocumentIngestionPipeline.cs)

Portal capability:
- "Why can I see this?" explainer for search hits
- Security ID inspection for ingested documents
- Warning banner when documents are org-wide due to missing source ACL

### 6) Deployment and Environment Diagnostics

Why:
- Customers and operators need faster troubleshooting for auth, model, and endpoint mismatch.

Use existing components:
- MCP auth and health surface in [src/DataAiMcp.McpServer/Program.cs](../src/DataAiMcp.McpServer/Program.cs)
- Deployment wiring in [infra/scripts/postprovision.sh](../infra/scripts/postprovision.sh)
- CI deployment logic in [.github/workflows/terraform.yml](../.github/workflows/terraform.yml)
- Operational runbook in [docs/DEPLOYMENT.md](DEPLOYMENT.md)

Portal capability:
- One-click diagnostics panel for MCP URL, audience, tenant, search index name, foundry deployment names
- "Fix hints" linked to exact runbook section
- Environment export page for support tickets

## Priority 3: Governance and customer adoption

### 7) Prompt Library and Business Scenarios

Why:
- Customers adopt faster when prompts are pre-built for their mission workflows.

Use existing components:
- Demo guidance in [docs/MCP-DEMO-RUNBOOK.md](MCP-DEMO-RUNBOOK.md)
- Dataset sample questions in [src/DataAiMcp.McpServer/appsettings.json](../src/DataAiMcp.McpServer/appsettings.json)

Portal capability:
- Scenario packs (engineering, logistics, compliance, readiness)
- Prompt templates with expected output shape and troubleshooting notes
- Favorite and share prompt flows

### 8) Source Quality and Coverage Dashboard

Why:
- Customers need to know data freshness and coverage before trusting responses.

Use existing components:
- Source metadata model in [src/DataAiMcp.McpServer/Tools/MetadataTools.cs](../src/DataAiMcp.McpServer/Tools/MetadataTools.cs)
- Ingestion failure modes in [docs/INGESTION.md](INGESTION.md)

Portal capability:
- Source-level freshness indicators
- Estimated document counts by source and trend line
- "Coverage gaps" list (configured but empty sources, stale sources)

### 9) Guided Customer Setup for New Tenants

Why:
- New customer onboarding currently requires deep platform knowledge.

Use existing components:
- Preconditions and sign-off checklist in [docs/DEPLOYMENT.md](DEPLOYMENT.md)
- Architecture decisions in [docs/README.md](README.md)

Portal capability:
- Step-by-step setup checklist with progress tracking
- Required values collection and validation
- Generate a customer onboarding report

## Recommended delivery sequence

Phase A (2-3 weeks):
- Source Catalog and Data Dictionary
- MCP Playground
- Ingestion Run Center (initial)

Phase B (2-3 weeks):
- Source Onboarding Wizard
- ACL and Access Visibility
- Deployment and Environment Diagnostics

Phase C (2-4 weeks):
- Prompt Library and Business Scenarios
- Source Quality and Coverage Dashboard
- Guided Customer Setup for New Tenants

## UX notes for customer ease-of-use

- Keep every page action-oriented: what happened, what to do next, and links to the exact guide page.
- Prefer progress states and checklists over raw JSON.
- Always surface generated SQL and citations where applicable so customers trust results.
- Show role and access context before any failing operation to reduce support tickets.

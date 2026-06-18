# Portal Architecture

## Purpose

The Data AI MCP Portal provides a single operator-facing web interface for the tasks that are currently performed with CLI commands:

- onboarding data into ADLS landing paths for ingestion
- triggering and observing Azure Data Factory (ADF) ingestion pipelines
- checking MCP endpoint readiness and authentication prerequisites
- following a guided onboarding checklist for demos and pilot deployments

The portal does not replace the MCP server. It is an operations and onboarding front end that integrates with the existing platform.

## Scope

Initial portal scope in this repository:

- environment dashboard with MCP health and auth audience visibility
- secure file upload workflow to storage landing container paths
- SQL demo pipeline trigger and activity summary view
- onboarding checklist and runbook links

Out of scope for the first increment:

- full RBAC admin tooling for Azure role assignments
- direct editing of Terraform variables and infra settings
- replacing existing CI/CD or deployment workflows

## Architecture

```mermaid
flowchart LR
    User[Portal User] --> Portal[DataAiMcp.Portal]\n
    Portal --> AppConfig[Portal Settings]\n    Portal --> MI[DefaultAzureCredential / Managed Identity]\n
    Portal --> Blob[Azure Blob Storage\nlanding container]
    Portal --> ADF[Azure Data Factory\nPipeline Runs API]
    Portal --> MCP[MCP Server\n/healthz and /mcp]

    Blob --> Ingest[Ingestion Functions]
    ADF --> Curated[ADLS Curated + Synapse Views]
    Ingest --> Search[Azure AI Search Index]
```

## Project Layout

A new project is added under `src/`:

- `src/DataAiMcp.Portal/`
- Razor Pages UI with thin application services
- no direct dependency on internal MCP server assemblies for first increment

Key folders:

- `Pages/` user-facing pages
- `Services/` Azure integration services
- `Models/` option and DTO classes

## Authentication and Authorization

Phase 1 (internal operations portal):

- portal is expected to run in an authenticated environment (App Service auth or network controls)
- Azure resource access uses `DefaultAzureCredential`
- local development path uses Azure CLI identity
- deployed path uses managed identity

Future hardening steps:

- enforce Entra auth in the portal app itself (Microsoft.Identity.Web)
- add role-based UI controls for operator vs reader personas
- add anti-forgery hardening and request throttling for trigger endpoints

## Data and Control Flows

### 1) Upload and ingest flow

1. User opens Upload page and selects a file.
2. Portal uploads file to configured landing path in blob storage.
3. Existing ingestion function processes blob, extracts/chunks, writes search documents.
4. User validates via MCP prompt or source listing.

### 2) SQL pipeline flow

1. User opens SQL Pipeline page and triggers configured pipeline.
2. Portal calls ADF create-run endpoint.
3. Portal polls pipeline run status and queries activity run summaries.
4. User sees copy metrics (`rowsCopied`, `filesWritten`, `dataRead`) in the portal.

### 3) MCP readiness flow

1. User opens Dashboard.
2. Portal calls `/healthz` on MCP endpoint.
3. Portal displays configured audience and troubleshooting hints for token acquisition.

## Configuration Model

Portal configuration is appsettings-driven via `PortalOptions`:

- `McpBaseUrl`
- `McpAudience`
- `SubscriptionId`
- `ResourceGroupName`
- `DataFactoryName`
- `SqlPipelineName`
- `StorageAccountUrl`
- `LandingContainerName`

Secrets are not stored in repository settings files.

## Operational Notes

- The portal wraps existing documented operations in `docs/MCP-DEMO-RUNBOOK.md`.
- The SQL pipeline helper script remains valid for CLI-first operators.
- Portal and CLI should produce equivalent run outcomes for demo ingestion.

## Testing Strategy

Minimum for this increment:

- compile/build validation with `dotnet build DataAiMcp.slnx`
- manual smoke:
  - dashboard health check
  - one small file upload to landing path
  - one SQL pipeline run and summary render

Planned follow-ups:

- unit tests for service classes with mocked `HttpClient`
- integration tests for pages with fake service adapters
- UI automation for onboarding happy path

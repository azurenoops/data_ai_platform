# Dynamic Source Onboarding Implementation

**Status**: Foundation complete, fetcher implementations pending

## What's Been Built

This implementation allows portal operators to onboard new data sources without code deployment, using a **dispatcher + configuration store** pattern.

### Core Components

#### 1. Shared Models & Interfaces (`src/DataAiMcp.Shared/Ingestion/`)

- **`SourceConfiguration.cs`** — Configuration record stored in CosmosDB
  - ID format: `{sourceType}-{guid}` (e.g., `teams-a1b2c3d4`)
  - Settings: flat dictionary of source-specific config
  - Tracks enabled state, last run, audit metadata

- **`ISourceFetcher.cs`** — Abstraction for source fetchers
  - `EnumerateAsync()` yields `(path, stream, securityIds)`
  - `ValidateAsync()` pre-flight checks before ingestion
  - Implementations: OneDrive, SharePoint, Teams, AWS S3, Google Drive (to be added)

- **`ISourceConfigurationStore.cs`** — Repository for persisting configurations
  - `CosmosSourceConfigurationStore.cs` — CosmosDB implementation
  - CRUD operations, filtering, last-run status updates

- **`ISourceFetcherFactory.cs`** & **`SourceFetcherFactory.cs`** — Factory pattern
  - Maps source types to fetcher instances
  - Extensible: new sources register via `Register(sourceType, fetcherType)`

#### 2. Dispatcher Function (`src/DataAiMcp.Ingestion.Functions/DispatcherFunction.cs`)

- Replaces legacy per-source timer functions with one dispatcher timer
- Runs on fixed 6-hour schedule
- Reads all enabled sources from CosmosDB
- For each source:
  - Retrieves fetcher from factory
  - Calls `EnumerateAsync()` with source settings
  - Uploads to `landing/{sourceType}/{sourceId}/{path}`
  - Updates last-run status in CosmosDB
- Continues on individual source failures (one source failing doesn't block others)

#### 3. Portal Services (`src/DataAiMcp.Portal/Services/`)

- **`ISourceConfigurationService.cs`** & **`SourceConfigurationService.cs`**
  - Portal business logic: validation, source creation, metadata management
  - `ValidateAndCreateAsync()` checks:
    - Source type is supported & implemented
    - Required settings are provided
    - Fetcher can validate source accessibility
  - `GetSupportedSourceTypes()` returns metadata for UI (settings schema, descriptions)

- **Portal Page:** `Pages/Admin/Sources.cshtml[.cs]`
  - Lists all configured sources with enable/disable/delete actions
  - Form to add new sources with dynamic field generation
  - Shows last-run status and audit trail per source
  - JavaScript dynamically populates settings form based on selected source type

## Configuration (appsettings.json)

### Portal
```json
{
  "CosmosDb": {
    "Endpoint": "https://<cosmosdb>.documents.azure.com:443/",
    "DatabaseId": "ingestion",
    "SourceConfigContainerId": "source-configurations"
  }
}
```

### Functions
```json
{
  "CosmosDb": {
    "Endpoint": "https://<cosmosdb>.documents.azure.com:443/",
    "DatabaseId": "ingestion",
    "SourceConfigContainerId": "source-configurations"
  }
}
```

## What's NOT Yet Done

### 1. Fetcher Implementations
Current fetchers (GraphFileFetcher for OneDrive/SharePoint) directly upload to blob storage. Need to refactor to support streaming:
- [ ] Refactor `GraphFileFetcher` to return items without uploading
- [ ] Implement `OneDriveSourceFetcher` (wraps refactored GraphFileFetcher)
- [ ] Implement `SharePointSourceFetcher`
- [ ] Implement `TeamsSourceFetcher` (new)
- [ ] Implement `AwsS3SourceFetcher` (new)
- [ ] Implement `GoogleDriveSourceFetcher` (new)
- [ ] Implement `AfsSourceFetcher` (new)

Once a fetcher is implemented:
1. Register in Functions `Program.cs`: `factory.Register("source-type", typeof(SourceFetcher))`
2. Update `SourceConfigurationService.GetSupportedSourceTypes()` to set `Implemented = true`
3. Portal becomes immediately functional for that source

### 2. Terraform Changes (Infrastructure)

- [x] Add CosmosDB account and SQL API database/container for source configurations
- [x] Create `source-configurations` container (partition key: `sourceType`)
- [x] Add app settings to Portal & Functions:
  - `CosmosDb__Endpoint`
  - `CosmosDb__DatabaseId`
  - `CosmosDb__SourceConfigContainerId`
- [x] Grant Portal & Functions UAMI Cosmos SQL data-plane contributor role
- [x] CI/CD deploys MCP server, Functions, and Portal run-from-package artifacts

### 3. Migration Status

Current architecture:
```
DispatcherFunction (timer) → ISourceFetcher → landing/
```

Transition plan:
1. Deploy dispatcher + factory + store (this PR)
2. Refactor fetchers incrementally (1-2 per sprint)
3. Operators use Portal to configure sources instead of `appsettings.json`
4. Complete fetcher implementations and enable source types in Portal metadata

## Security Model

- **Portal Access**: `@AuthorizeFolder("/")` — all authenticated users
  - Future: RBAC constraint to "Ingestion Operator" role
  - Audit: `CreatedBy`, `ModifiedBy` track operator identity (AAD OID)
  
- **Source Secrets**:
  - Settings dict stored in CosmosDB (e.g., AWS bucket names, OneDrive drive IDs)
  - Sensitive values (API keys, tokens) should NOT be stored; use Managed Identity / OIDC federation instead
  - Validation phase (`ValidateAsync()`) can enforce "no secrets in settings"

- **securityIds**: Per-document ACL metadata persists through ingestion pipeline
  - Fetcher responsible for resolving per-source ACLs to AAD object IDs
  - RagOrchestrator applies filter at search time

## Testing

- [ ] Unit tests for `SourceFetcherFactory`
- [ ] Unit tests for `SourceConfigurationService` validation
- [ ] Integration tests for `DispatcherFunction` (mock fetchers)
- [ ] Smoke tests: create source via Portal → verify DispatcherFunction processes it → check landing blobs

## Monitoring & Observability

- DispatcherFunction logs per source:
  - Fetch start/end, item count
  - Validation failures, blob upload retries
  - LastRunStatus persisted in CosmosDB (queryable via Portal)
  
- Dashboard opportunity:
  - Per-source ingestion timeline
  - Failure rate by source type
  - Total documents ingested per source

## Next Steps

1. **Refactor GraphFileFetcher** to return items without uploading (blocking for OneDrive/SharePoint)
2. **Implement Teams fetcher** (Teams channels → landing/)
3. **Update Terraform** with CosmosDB and RBAC
4. **Smoke tests** for end-to-end flow
5. **Portal RBAC** (restrict to Ingestion Operator role)

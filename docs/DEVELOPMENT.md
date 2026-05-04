# Development Guide — Data + AI + MCP Platform

End-to-end guide to **developing**, **extending**, and **enhancing** this solution. Read this if you are about to add a new MCP tool, wire a new ingestion source, change the chunker, change the index schema, swap a model, or otherwise modify behavior.

This guide is the development companion to:
- [docs/README.md](README.md) — value, audience, decisions, pitfalls.
- [docs/DEPLOYMENT.md](DEPLOYMENT.md) — step-by-step deployment to Flank Speed / Azure Government.
- [README.md](../README.md) — operator quick reference.

---

## Table of contents

1. [Solution overview](#1-solution-overview)
2. [Development environment setup](#2-development-environment-setup)
3. [Repository layout in detail](#3-repository-layout-in-detail)
4. [Coding standards and conventions](#4-coding-standards-and-conventions)
5. [Local inner-loop workflow](#5-local-inner-loop-workflow)
6. [Configuration model](#6-configuration-model)
7. [Adding a new MCP tool](#7-adding-a-new-mcp-tool)
8. [Adding a new ingestion source](#8-adding-a-new-ingestion-source)
9. [Adding a new structured dataset](#9-adding-a-new-structured-dataset)
10. [Evolving the search index schema](#10-evolving-the-search-index-schema)
11. [Changing the embedding model](#11-changing-the-embedding-model)
12. [Changing the chat model or the SQL generation prompt](#12-changing-the-chat-model-or-the-sql-generation-prompt)
13. [Working with infrastructure (Terraform)](#13-working-with-infrastructure-terraform)
14. [Authentication, authorization, and ACL trimming](#14-authentication-authorization-and-acl-trimming)
15. [Telemetry and observability](#15-telemetry-and-observability)
16. [Testing strategy](#16-testing-strategy)
17. [Branching, commits, code review](#17-branching-commits-code-review)
18. [CI/CD pipelines](#18-cicd-pipelines)
19. [Performance tuning](#19-performance-tuning)
20. [Security and supply chain](#20-security-and-supply-chain)
21. [Common development tasks — recipes](#21-common-development-tasks--recipes)
22. [Pitfalls specific to development](#22-pitfalls-specific-to-development)
23. [Appendix A — File-by-file extension map](#appendix-a--file-by-file-extension-map)
24. [Appendix B — Definition of Done checklist](#appendix-b--definition-of-done-checklist)

---

## 1. Solution overview

The solution is a single Visual Studio solution file ([DataAiMcp.slnx](../DataAiMcp.slnx)) wired through .NET 9 Central Package Management.

| Project | Type | Role |
| --- | --- | --- |
| [src/DataAiMcp.McpServer](../src/DataAiMcp.McpServer) | ASP.NET Core 9 web app | Hosts the MCP HTTP endpoint at `/mcp`, JWT bearer auth, tool registrations. |
| [src/DataAiMcp.Ingestion.Functions](../src/DataAiMcp.Ingestion.Functions) | Azure Functions (dotnet-isolated) | Blob trigger + timer triggers for SharePoint / OneDrive ingestion + curation. |
| [src/DataAiMcp.Shared](../src/DataAiMcp.Shared) | Class library | All cross-cutting code: Auth, AI clients, document chunking, search schema, storage, telemetry, models, DI extensions. |
| [src/DataAiMcp.Tools.IndexProvisioner](../src/DataAiMcp.Tools.IndexProvisioner) | Console tool | Idempotent AI Search index provisioning. Invoked from [infra/scripts/postprovision.sh](../infra/scripts/postprovision.sh) after `terraform apply`. |
| [src/Samples/DataAiMcp.SampleClient.Console](../src/Samples/DataAiMcp.SampleClient.Console) | Console | Reference MCP client for smoke testing and demos. |
| [tests/DataAiMcp.Shared.Tests](../tests/DataAiMcp.Shared.Tests) | xUnit | Unit tests for chunker + schema. |
| [tests/DataAiMcp.McpServer.Tests](../tests/DataAiMcp.McpServer.Tests) | xUnit + WebApplicationFactory | In-process integration tests for the MCP server. |
| [tests/DataAiMcp.Functions.Tests](../tests/DataAiMcp.Functions.Tests) | xUnit | Pipeline smoke tests. |
| [tests/DataAiMcp.Smoke.Tests](../tests/DataAiMcp.Smoke.Tests) | xUnit | End-to-end smoke against a deployed environment. Run from [infra/scripts/postdeploy.sh](../infra/scripts/postdeploy.sh) after the App Service zip-deploy. |
| [infra](../infra) | Terraform + scripts + DDL | Subscription-scoped Terraform (15 modules + bootstrap), ADF pipelines, Synapse view DDL, post-provision/post-deploy hooks. |

Cross-cutting principles:

- **One DI extension wires everything**: [SharedServiceCollectionExtensions.AddDataAiShared](../src/DataAiMcp.Shared/DependencyInjection/SharedServiceCollectionExtensions.cs) is called from both the MCP server's `Program.cs` and the Function App's `Program.cs`. New shared services should register there.
- **No static state**, no service-locator. Everything is constructor-injected.
- **No shared secrets at runtime**. `AzureCredentialFactory` produces a single `TokenCredential` per process and every Azure SDK client takes that credential.
- **Telemetry is namespaced**: `DataAiTelemetry.SourceName` / `DataAiTelemetry.MeterName` for tracing/metrics across both processes.

---

## 2. Development environment setup

### 2.1 Required tools

| Tool | Version | Purpose |
| --- | --- | --- |
| .NET SDK | `9.0.100` (pinned by [global.json](../global.json)) | Build, test, run. |
| Azure CLI (`az`) | `2.60+` | Cloud login, ad-hoc operations. |
| Terraform | `1.9.0+` | Provision (CI uses `1.9.8`). Install from `hashicorp/tap` on macOS or HashiCorp releases page. |
| Azure Functions Core Tools | v4 | Run the Function App locally with `func start`. |
| Azurite | latest | Local blob/queue emulator for Functions. |
| `tflint` (optional) | `v0.55+` | Lint Terraform locally; CI enforces. |
| Git | any modern version | — |
| `sqlcmd` (with `-G` AAD support) | 18+ | Optional: push Synapse view DDL. |

> If you intend to develop against the **deployed** dev environment (recommended for ingestion work — emulating Document Intelligence and Foundry locally is not worth the effort), you only strictly need .NET, `az`, and `terraform` (for reading outputs and reapplying small changes).

### 2.2 Recommended tools

- **VS Code** with the C# Dev Kit extension or **JetBrains Rider**.
- The **Azure Developer CLI** VS Code extension.
- The **Terraform** (HashiCorp) VS Code extension.

### 2.3 First-time bring-up

```bash
git clone <repo-url> data-ai-mcp
cd data-ai-mcp

dotnet restore DataAiMcp.slnx
dotnet build   DataAiMcp.slnx -c Debug
dotnet test    DataAiMcp.slnx -c Debug --no-build
```

Expected: green build, all tests pass. If unit tests fail on a clean clone, **stop** and fix that before any other change — the codebase treats warnings as errors and the test gate is the primary safety net.

### 2.4 Editor setup

- C# editor config is enforced through [Directory.Build.props](../Directory.Build.props): `TreatWarningsAsErrors=true`, `Nullable=enable`, `AnalysisLevel=latest-recommended`.
- The `NoWarn` list in that file is the **only** place where suppressed analyzers should live. Do not add `#pragma warning disable` in source files unless the warning is genuinely unactionable and a comment explains why.

---

## 3. Repository layout in detail

### 3.1 `src/DataAiMcp.McpServer`

```
DataAiMcp.McpServer/
├── Program.cs                        # ASP.NET host, auth, MCP server, OTel
├── DataAiMcp.McpServer.csproj
├── appsettings.json                  # Defaults; env-vars override at runtime
├── appsettings.Development.json
├── Auth/
│   ├── McpAuthOptions.cs             # Auth:* config binding
│   ├── McpPolicies.cs                # Policy name constants
│   └── CallerSecurityContext.cs      # Per-request ACL extraction (HttpContext-scoped)
├── Rag/
│   └── RagOrchestrator.cs            # search_documents / get_document core
├── Resources/
│   └── CuratedDocumentResources.cs   # MCP "resources" surface for indexed docs
├── Synapse/
│   ├── SqlGenerator.cs               # NL → T-SQL (Foundry chat)
│   └── SynapseQueryClient.cs         # ADO.NET execution + row cap + AAD auth
└── Tools/
    ├── SearchTools.cs                # search_documents, get_document
    ├── StructuredTools.cs            # query_structured_data, describe_dataset
    └── MetadataTools.cs              # list_sources
```

### 3.2 `src/DataAiMcp.Ingestion.Functions`

```
DataAiMcp.Ingestion.Functions/
├── Program.cs                        # Functions host + DI
├── host.json
├── local.settings.template.json      # Copy → local.settings.json for local dev
├── IngestBlobFunction.cs             # BlobTrigger("landing/{name}")
├── SharePointFilesFunction.cs        # Timer trigger, Graph SharePoint pull
├── OneDriveFilesFunction.cs          # Timer trigger, Graph OneDrive pull
├── CurationFunction.cs               # Optional curation step, raw → curated
├── Graph/
│   ├── GraphClientFactory.cs         # MUST be retargeted to graph.microsoft.us for Gov
│   └── GraphFileFetcher.cs
└── Pipeline/
    └── DocumentIngestionPipeline.cs  # DI → chunk → embed → upsert
```

### 3.3 `src/DataAiMcp.Shared`

```
DataAiMcp.Shared/
├── Ai/                               # FoundryClientFactory, FoundryOptions
├── Auth/                             # AzureCredentialFactory, AzureCredentialOptions
├── DependencyInjection/
│   └── SharedServiceCollectionExtensions.cs   # AddDataAiShared(...)
├── Documents/
│   ├── DocumentLayoutExtractor.cs    # DocIntel layout → markdown
│   └── MarkdownChunker.cs            # Heading-aware chunking + cl100k_base tokens
├── Models/
│   └── Models.cs                     # IndexDocument, SearchHit, DatasetDescriptor, ...
├── Search/
│   ├── SearchIndexSchema.cs          # Field names, vector profile, semantic config
│   ├── SearchIndexProvisioner.cs     # CreateOrUpdate index
│   └── IIndexWriter.cs               # Upsert abstraction (incl. dual-write DR variant)
├── Storage/
│   └── DataLakeRepository.cs         # ADLS Gen2 helpers; container constants
└── Telemetry/
    └── DataAiTelemetry.cs            # ActivitySource + Meter constants
```

### 3.4 `infra/`

See [docs/DEPLOYMENT.md](DEPLOYMENT.md) for the full module table. Key files relevant to development:

- [infra/main.tf](../infra/main.tf) — top-level subscription deployment, all parameters.
- [infra/envs/dev.tfvars](../infra/envs/dev.tfvars) — `azd` parameter binding.
- [infra/modules/foundry/main.tf](../infra/modules/foundry/main.tf) — model deployments. Edit here when changing models.
- [infra/modules/roleassignments/main.tf](../infra/modules/roleassignments/main.tf) — RBAC. Edit here when adding new data-plane access.
- [infra/synapse/views/*.sql](../infra/synapse/views) — view DDL. Add a file here for a new dataset.
- [infra/datafactory/pipelines/*.json](../infra/datafactory/pipelines) — pipeline JSON. Add when wiring a new structured source.

---

## 4. Coding standards and conventions

### 4.1 Compiler settings

Defined in [Directory.Build.props](../Directory.Build.props) — applies to every project automatically:

- `TargetFramework=net9.0`
- `LangVersion=latest`
- `Nullable=enable`
- `ImplicitUsings=enable`
- `TreatWarningsAsErrors=true`
- `EnforceCodeStyleInBuild=true`
- `AnalysisLevel=latest-recommended`

The build will fail on:
- Null-warning leaks.
- Code style violations.
- IDE/CA analyzer warnings not on the `NoWarn` allow-list.

### 4.2 Naming

- Class library namespaces follow folder names (`DataAiMcp.Shared.Documents` lives under `Shared/Documents/`).
- Tool classes are `sealed` and named `<Capability>Tools` (`SearchTools`, `StructuredTools`).
- Options classes follow the pattern `<Feature>Options` and expose a `public const string SectionName`.
- Tests are `<TypeUnderTest>Tests`.

### 4.3 Async, cancellation, and disposal

- Every async public method takes `CancellationToken cancellationToken` and forwards it.
- `.ConfigureAwait(false)` is used in library code — `Directory.Build.props` suppresses `CA2007`, but **only library code** drops the synchronization context. Top-level program files do not need the suffix.
- Use `await using` for `IAsyncDisposable`.
- Do not introduce `async void` — analyzer will fail the build.

### 4.4 Logging

- Use the `Microsoft.Extensions.Logging.ILogger<T>` injected pattern. `LoggerMessage`-source-generated logging is not currently used; templated strings are acceptable (`CA1848` is suppressed).
- Log **identifiers, not bodies** — log the blob name, not the blob contents; log the document ID, not the chunk text.
- INFO for happy-path lifecycle events; WARN for skips/recoverable; ERROR for failures the operator must know about.

### 4.5 Configuration

- All configuration goes through `IOptions<T>`. Bind options classes in [SharedServiceCollectionExtensions.cs](../src/DataAiMcp.Shared/DependencyInjection/SharedServiceCollectionExtensions.cs) or in the host's `Program.cs`.
- Never call `IConfiguration["X:Y"]` directly outside a binder method — it bypasses validation.
- Use `[DataAnnotations]` attributes plus `.ValidateDataAnnotations()` for required values.

### 4.6 Dependency injection

- Constructor injection only. No field injection, no service-locator (`IServiceProvider.GetService` in business code).
- Singletons are the default. Use `AddScoped` only if the dependency holds per-request state — `CallerSecurityContext` is the canonical example, and it relies on `IHttpContextAccessor`.

### 4.7 Public-API surface in `DataAiMcp.Shared`

`DataAiMcp.Shared` is consumed by the MCP server, the Functions, the IndexProvisioner, and the smoke tests. **A breaking change in this project is a breaking change everywhere.** When you alter a public type, run a full solution build before pushing.

---

## 5. Local inner-loop workflow

### 5.1 Build & test

```bash
dotnet build DataAiMcp.slnx -c Debug
dotnet test  DataAiMcp.slnx -c Debug --no-build
```

Run a single test project:

```bash
dotnet test tests/DataAiMcp.Shared.Tests/DataAiMcp.Shared.Tests.csproj
```

### 5.2 Run the MCP server locally

The MCP server can run against either:

- **A deployed Azure dev environment** (recommended) — uses real AI Search, Foundry, Synapse, Storage. Auth toggled off via `Auth:RequireAuthenticatedUser=false`.
- **An entirely local stand-in** — only useful for the HTTP plumbing, not the data plane.

Set up against the deployed environment:

```bash
terraform -chdir=infra output -json | jq -r 'to_entries[] | "export " + .key + "=" + (.value.value | @sh)' > /tmp/.dataaimcp.env
source /tmp/.dataaimcp.env

cd src/DataAiMcp.McpServer

# Run with auth off so you don't need to mint a token for every test.
dotnet run -- \
  --Auth:RequireAuthenticatedUser=false \
  --Search:Endpoint=$SEARCH_ENDPOINT \
  --Foundry:Endpoint=$FOUNDRY_ACCOUNT_ENDPOINT \
  --Foundry:ChatDeployment=$FOUNDRY_CHAT_DEPLOYMENT \
  --Foundry:EmbeddingDeployment=$FOUNDRY_EMBEDDING_DEPLOYMENT \
  --Synapse:ServerlessSqlEndpoint=$SYNAPSE_SERVERLESS_SQL_ENDPOINT \
  --Storage:AccountName=$STORAGE_ACCOUNT_NAME
```

The server listens on `http://localhost:5xxx` — check the launch settings in [src/DataAiMcp.McpServer/Properties/launchSettings.json](../src/DataAiMcp.McpServer/Properties/launchSettings.json).

### 5.3 Run the Functions locally

```bash
cd src/DataAiMcp.Ingestion.Functions
cp local.settings.template.json local.settings.json   # one-time
# Fill in values from `terraform -chdir=infra output -json | jq`.

func start
```

Notes:
- The blob trigger requires Azurite or a real storage account on `AzureWebJobsStorage`. Easiest path: point at the dev environment's storage account.
- Timer triggers fire on their schedule; to test once, change the cron in the function attribute or invoke the function HTTP admin endpoint.

### 5.4 Run the IndexProvisioner

```bash
source /tmp/.dataaimcp.env
dotnet run --project src/DataAiMcp.Tools.IndexProvisioner
```

Idempotent — safe to run repeatedly.

### 5.5 Use the sample client

```bash
dotnet run --project src/Samples/DataAiMcp.SampleClient.Console -- \
  http://localhost:5xxx \
  api://localhost-no-auth
```

When pointed at a deployed environment, replace the URL with `MCP_SERVER_BASE_URL` and the audience with `api://<APP_SERVICE_NAME>`.

### 5.6 Trigger ingestion manually

```bash
RG=$(terraform -chdir=infra output -raw AZURE_RESOURCE_GROUP)
ACCT=$(terraform -chdir=infra output -raw STORAGE_ACCOUNT_NAME)

az storage blob upload \
  --account-name "$ACCT" \
  --container-name landing \
  --name pilot/sample.pdf \
  --file ./samples/sample.pdf \
  --auth-mode login
```

Within a few seconds the blob trigger fires; tail the Function App logs to watch the pipeline. The chunked output appears in `chunks/` and the embedded vectors appear in AI Search.

---

## 6. Configuration model

### 6.1 Hierarchy

For both the MCP server and the Functions:

1. `appsettings.json` — repository defaults.
2. `appsettings.<Environment>.json` — environment overrides (Development).
3. Environment variables — emitted by `azd` and by Bicep into the App Service / Function App settings.
4. Command-line arguments — useful for local overrides.

### 6.2 Section reference

| Section | Used by | Source of truth |
| --- | --- | --- |
| `Auth` | MCP server | [Auth/McpAuthOptions.cs](../src/DataAiMcp.McpServer/Auth/McpAuthOptions.cs) |
| `Storage` | Both | [src/DataAiMcp.Shared/Storage](../src/DataAiMcp.Shared/Storage) |
| `Search` | Both | [src/DataAiMcp.Shared/Search](../src/DataAiMcp.Shared/Search) |
| `Foundry` | Both | [src/DataAiMcp.Shared/Ai](../src/DataAiMcp.Shared/Ai) |
| `Synapse` | MCP server | [Synapse/SynapseQueryClient.cs](../src/DataAiMcp.McpServer/Synapse/SynapseQueryClient.cs) |
| `Datasets` | MCP server | [appsettings.json](../src/DataAiMcp.McpServer/appsettings.json) — bound into `DatasetCatalogOptions`. |
| `Sources` | MCP server | Same — bound into `SourceCatalogOptions`. |
| `Graph` | Functions | [Graph/GraphClientFactory.cs](../src/DataAiMcp.Ingestion.Functions/Graph/GraphClientFactory.cs) |
| `SharePoint`, `OneDrive` | Functions | The respective trigger functions. |
| `DocumentIntelligence` | Functions | [src/DataAiMcp.Shared/Documents/DocumentLayoutExtractor.cs](../src/DataAiMcp.Shared/Documents/DocumentLayoutExtractor.cs) |
| `Chunker` | Functions | [SharedServiceCollectionExtensions.cs](../src/DataAiMcp.Shared/DependencyInjection/SharedServiceCollectionExtensions.cs) |

### 6.3 Adding a new configuration value

1. Add the property to the relevant `*Options` class. If you have to create a new options class, follow the convention:
   ```csharp
   public sealed class MyFeatureOptions
   {
       public const string SectionName = "MyFeature";
       [Required] public string Endpoint { get; set; } = "";
   }
   ```
2. Bind it in the appropriate `Add...` method (typically [SharedServiceCollectionExtensions.cs](../src/DataAiMcp.Shared/DependencyInjection/SharedServiceCollectionExtensions.cs)).
3. Add the default to [appsettings.json](../src/DataAiMcp.McpServer/appsettings.json) (or the Functions equivalent if relevant).
4. If the value must come from the deployment, surface it as a Terraform output in [infra/outputs.tf](../infra/outputs.tf) and wire it through the App Service / Function App `app_settings` in [infra/primary.tf](../infra/primary.tf) (and [infra/modules/regional/main.tf](../infra/modules/regional/main.tf) for DR).
5. Update [docs/DEPLOYMENT.md](DEPLOYMENT.md) with the new environment variable.

---

## 7. Adding a new MCP tool

This is the most common extension. Follow this pattern.

### 7.1 Anatomy of an MCP tool

Tool classes are decorated with `[McpServerToolType]`. Methods are decorated with `[McpServerTool(Name = "...")]` and `[Description("...")]` and use parameter `[Description("...")]` attributes for argument metadata. The MCP framework reflects over this and exposes the tool to clients automatically.

Reference: [SearchTools.cs](../src/DataAiMcp.McpServer/Tools/SearchTools.cs).

### 7.2 Step-by-step — adding `lookup_nsn`

Hypothetical example: surface a National Stock Number lookup against an existing supply view in Synapse.

**Step 1 — create the tool class** in [src/DataAiMcp.McpServer/Tools/SupplyTools.cs](../src/DataAiMcp.McpServer/Tools):

```csharp
using System.ComponentModel;
using DataAiMcp.McpServer.Synapse;
using ModelContextProtocol.Server;

namespace DataAiMcp.McpServer.Tools;

[McpServerToolType]
public sealed class SupplyTools
{
    private readonly SynapseQueryClient _synapse;

    public SupplyTools(SynapseQueryClient synapse) => _synapse = synapse;

    [McpServerTool(Name = "lookup_nsn")]
    [Description("Look up a National Stock Number against the curated supply view; returns description, UI, price, and last-updated.")]
    public async Task<IReadOnlyList<IReadOnlyDictionary<string, object?>>> LookupAsync(
        [Description("National Stock Number, e.g. '5305-00-123-4567'.")] string nsn,
        CancellationToken cancellationToken = default)
    {
        var sql = $"SELECT TOP 1 nsn, item_name, ui, unit_price, last_updated FROM dbo.vw_supply_catalog WHERE nsn = '{nsn.Replace("'", "''")}'";
        var rows = await _synapse.ExecuteAsync(sql, cancellationToken).ConfigureAwait(false);
        return rows.Rows;
    }
}
```

> The example uses a parameterized query through `SynapseQueryClient` rather than directly composing SQL. Replace the inlined SQL with whatever execution pattern is appropriate; do not introduce SQL injection risk by interpolating untrusted strings.

**Step 2 — register the tool** in [src/DataAiMcp.McpServer/Program.cs](../src/DataAiMcp.McpServer/Program.cs):

```csharp
builder.Services.AddMcpServer()
    .WithHttpTransport()
    .WithTools<SearchTools>()
    .WithTools<StructuredTools>()
    .WithTools<MetadataTools>()
    .WithTools<SupplyTools>();   // <-- new
```

**Step 3 — wire any new dependencies**. If the tool uses an existing service (`SynapseQueryClient` is already singleton), no extra work. If it requires a new service:

```csharp
builder.Services.AddSingleton<MyNewClient>();
```

**Step 4 — add unit tests** in [tests/DataAiMcp.McpServer.Tests](../tests/DataAiMcp.McpServer.Tests):

```csharp
public sealed class SupplyToolsTests
{
    [Fact]
    public async Task Lookup_returns_row()
    {
        var fakeSynapse = new FakeSynapseQueryClient(rows: [
            new Dictionary<string, object?>{ ["nsn"] = "5305-00-123-4567" }
        ]);
        var tool = new SupplyTools(fakeSynapse);

        var result = await tool.LookupAsync("5305-00-123-4567");

        result.Should().HaveCount(1);
    }
}
```

**Step 5 — verify end-to-end** with the sample client:

```bash
dotnet run --project src/Samples/DataAiMcp.SampleClient.Console -- ...
```

The new tool appears automatically in `tools/list`.

**Step 6 — gate authorization** if the tool needs elevated access. The default policy is `ReadDocuments`. If `lookup_nsn` should require an admin role, attribute the method or apply `RequireAuthorization` on the MCP endpoint mapping in `Program.cs` keyed by tool name (see the MCP framework documentation; the cleanest way today is to throw a `ForbiddenAccessException` from the tool method when the caller's role claim is missing).

### 7.3 Tool design checklist

- [ ] Single, narrow responsibility. A tool does one thing.
- [ ] Returns a typed result that serializes cleanly (records or POCOs with public properties).
- [ ] Parameter descriptions tell the LLM what the argument means.
- [ ] Cancellation token forwarded to every awaited call.
- [ ] No mutable shared state — singletons are fine, mutable singletons are not.
- [ ] Logs identifiers but never raw response bodies.
- [ ] Tested with at least one happy-path unit test.
- [ ] Documented in [docs/README.md](README.md) "What you can do with it" if user-visible.

---

## 8. Adding a new ingestion source

Detailed extension recipes have moved to the [Ingestion guide](../docs/INGESTION.md):

- For onboarding a new tenant or new instance of an **existing** source type (drives, lists, tables), see the relevant per-source cookbook under [`docs/ingestion/`](../docs/ingestion/).
- For adding a brand-new **source type** (a new connector class, e.g., S3 / Box / Confluence), see [`docs/ingestion/adding-a-source-type.md`](../docs/ingestion/adding-a-source-type.md). That page includes:
  - The decision tree (Function vs. ADF vs. blob drop)
  - Function class skeleton + DI wiring
  - ADF pipeline + module pattern
  - Updates to `SearchIndexSchema`
  - Telemetry tagging
  - The cookbook template for documenting the new source

Architectural extension points kept in this document:

- **`IIndexWriter` / `IEmbeddingClient`** — replace these to swap search backends or embedding providers; see [`src/DataAiMcp.Shared/Search/`](../src/DataAiMcp.Shared/Search/) and [`src/DataAiMcp.Shared/Ai/`](../src/DataAiMcp.Shared/Ai/).
- **Chunker strategy** — `MarkdownChunker` is the default; alternative chunkers can be registered in DI in [`src/DataAiMcp.Ingestion.Functions/Program.cs`](../src/DataAiMcp.Ingestion.Functions/Program.cs).
- **Source registration in `appsettings.json`** — the `Sources` array drives `list_sources` and `search_documents`'s optional `source` filter; new sources should add an entry in [`src/DataAiMcp.McpServer/appsettings.json`](../src/DataAiMcp.McpServer/appsettings.json).

### Source onboarding checklist (cross-cutting)

- [ ] Data owner has signed off on the specific source location, in writing.
- [ ] Per-source allow list configured (no wildcards).
- [ ] Managed identity has only the read scopes necessary.
- [ ] Source name registered in `Sources` config so `list_sources` reports it.
- [ ] At least one document successfully ingested in dev.
- [ ] Smoke test extended (or sample question added) for that source.

---

## 9. Adding a new structured dataset

Three artifacts must move together: the **Synapse view** (DDL), the **dataset catalog entry** (config), and optionally a **sample question** (config).

### 9.1 Author the Synapse view

Add a file to [infra/synapse/views](../infra/synapse/views):

```sql
-- vw_nswc_phd_casreps.sql
CREATE OR ALTER VIEW dbo.vw_nswc_phd_casreps AS
SELECT
    casrep_id,
    hull,
    system,
    priority,
    open_date,
    status
FROM OPENROWSET(
    BULK 'https://__STORAGE_ACCOUNT__.dfs.core.usgovcloudapi.net/curated/casreps/*.parquet',
    FORMAT = 'PARQUET'
) AS src;
```

The post-provision script substitutes `__STORAGE_ACCOUNT__` and either pushes the SQL automatically (if you uncomment the `sqlcmd` line) or stages it for manual push.

### 9.2 Register the dataset

Add an entry to `Datasets` in [src/DataAiMcp.McpServer/appsettings.json](../src/DataAiMcp.McpServer/appsettings.json):

```jsonc
{
  "Name": "nswc_phd_casreps",
  "Description": "Open and historical Casualty Reports for systems NSWC PHD is the ISEA for.",
  "ViewName": "vw_nswc_phd_casreps",
  "Columns": [
    { "Name": "casrep_id", "DataType": "nvarchar(50)", "Description": "Casualty report id." },
    { "Name": "hull", "DataType": "nvarchar(20)", "Description": "Hull number." },
    { "Name": "system", "DataType": "nvarchar(200)", "Description": "Affected system." },
    { "Name": "priority", "DataType": "int", "Description": "P1..P4." },
    { "Name": "open_date", "DataType": "date", "Description": "Date opened." },
    { "Name": "status", "DataType": "nvarchar(40)", "Description": "Open / Closed / Pending." }
  ],
  "SampleQuestions": [
    "Open Priority 1 CASREPs in the last 30 days",
    "Top hulls by open CASREP count this quarter"
  ]
}
```

### 9.3 Push the view

```bash
eval "$(terraform -chdir=infra output -json | jq -r 'to_entries[] | "export " + .key + "=" + (.value.value | @sh)')"
sed "s/__STORAGE_ACCOUNT__/${STORAGE_ACCOUNT_NAME}/g" infra/synapse/views/vw_nswc_phd_casreps.sql \
  | sqlcmd -S "${SYNAPSE_SERVERLESS_SQL_ENDPOINT}" -G -d master
```

### 9.4 Restart the MCP server

App Service settings change → restart so the dataset catalog reloads:

```bash
az webapp restart -n "$(terraform -chdir=infra output -raw APP_SERVICE_NAME)" -g "$(terraform -chdir=infra output -raw AZURE_RESOURCE_GROUP)"
```

### 9.5 Validate

Use the sample client:

```
> tools/call describe_dataset { "name": "nswc_phd_casreps" }
> tools/call query_structured_data { "question": "Open Priority 1 CASREPs in the last 30 days", "dataset": "nswc_phd_casreps" }
```

The `query_structured_data` response includes `generatedSql` so you can inspect the model's output before trusting it.

---

## 10. Evolving the search index schema

The schema is declared once in [SearchIndexSchema.cs](../src/DataAiMcp.Shared/Search/SearchIndexSchema.cs). Both the IndexProvisioner (creates/updates the index) and the MCP server (reads it) reference the same constants.

### 10.1 Backwards-compatible field additions

Adding a new **filterable** or **simple** field is safe — `CreateOrUpdateIndex` will add it to the existing index without re-embedding.

```csharp
new SimpleField("classification", SearchFieldDataType.String) { IsFilterable = true, IsFacetable = true },
```

After deploy, run the provisioner. Existing documents have a null/empty value for the new field; new ingestions populate it.

### 10.2 Breaking changes

These require a full re-index:

- Changing the embedding dimension (`EmbeddingDimensions`).
- Changing the vector profile or HNSW parameters.
- Changing the analyzer on a searchable field.
- Renaming a field.

Procedure:

1. Bump `IndexName` to a new versioned name (`documents-v2`) — keep the old index online until cutover.
2. Update `SearchIndexSchema.IndexName` and any references in `RagOrchestrator`, `IIndexWriter`, `appsettings.json` (`Search:IndexName`).
3. Deploy.
4. Re-run ingestion against the source corpus.
5. Validate `documents-v2` returns expected hits.
6. Switch `Search:IndexName` to `documents-v2` for the MCP server (zero-downtime cutover via App Service slot if available).
7. Decommission `documents-v1`.

### 10.3 Schema unit test

The repository has [tests/DataAiMcp.Shared.Tests/SearchIndexSchemaTests.cs](../tests/DataAiMcp.Shared.Tests/SearchIndexSchemaTests.cs) — extend it whenever you change `SearchIndexSchema.Build()`.

---

## 11. Changing the embedding model

Embedding model changes are versioned decisions. Treat them as such.

### 11.1 Decide the new model

- It must be deployed in your Foundry / Azure OpenAI account.
- Note its **dimension** — `text-embedding-3-large` is 3072. `text-embedding-3-small` is 1536.

### 11.2 Update Bicep

Override at deploy time by editing your [infra/envs/<env>.tfvars](../infra/envs/) and re-running `terraform apply`:

```bash
# Edit infra/envs/<env>.tfvars: embedding_deployment = "my-embedding-model-v2"
terraform apply -var-file=envs/<env>.tfvars
```

### 11.3 Update the schema

In [SearchIndexSchema.cs](../src/DataAiMcp.Shared/Search/SearchIndexSchema.cs):

```csharp
public const int EmbeddingDimensions = 1536; // <- new dimension
```

### 11.4 Re-create the index

The dimension change is breaking. Follow the procedure in [§10.2](#102-breaking-changes) — version the index, run the provisioner, re-embed.

### 11.5 Re-embed the corpus

There is no "re-embed only" path today. The simplest approach: drop the old index and re-run ingestion.

Cost considerations:

- Re-embedding scales with token count of the entire corpus.
- For a large NSWC PHD corpus (technical manuals, instructions, ISEA work packages), this is non-trivial. Get a token estimate before kicking it off.

### 11.6 Update tests

[tests/DataAiMcp.Shared.Tests/SearchIndexSchemaTests.cs](../tests/DataAiMcp.Shared.Tests/SearchIndexSchemaTests.cs) asserts the dimension. Update the assertion.

---

## 12. Changing the chat model or the SQL generation prompt

### 12.1 Chat deployment

Two settings:

- `Foundry:ChatDeployment` — used by [SqlGenerator](../src/DataAiMcp.McpServer/Synapse/SqlGenerator.cs) and any other chat callers.
- The Bicep parameter `chatDeployment` — must match. The deployment must exist in Foundry first.

Override at deploy time:

```bash
# Edit infra/envs/<env>.tfvars: chat_deployment = "my-chat-model"
terraform apply -var-file=envs/<env>.tfvars
```

### 12.2 SQL generation prompt

The system prompt that constrains SQL generation lives in [SqlGenerator.cs](../src/DataAiMcp.McpServer/Synapse/SqlGenerator.cs). When editing:

- Keep it strict. The current prompt blocks DDL, multiple statements, semicolons, temp tables, procedures, prose. Don't relax those rules without compensating validation.
- Keep `Temperature = 0.0f`.
- Whatever you add to the prompt, add a corresponding **server-side validation** in [SynapseQueryClient.ExecuteAsync](../src/DataAiMcp.McpServer/Synapse/SynapseQueryClient.cs). The model is part of your defense; the validator is the rest.
- Add a unit test that feeds a malicious prompt (e.g., asking for `DROP TABLE`) and asserts the server rejects the generated SQL.

### 12.3 PII spillage in summarization

`query_structured_data` does not currently summarize rows back through the model — it returns raw rows plus the generated SQL. If you add a summarization step, do it consciously: row content will transit Foundry tokens. Document the decision in the ATO package.

---

## 13. Working with infrastructure (Terraform)

> The IaC was migrated from Bicep + `azd` to **Terraform**. The 15 modules live under [infra/modules/](../infra/modules), the root composition is in [infra/main.tf](../infra/main.tf) / [infra/primary.tf](../infra/primary.tf) / [infra/secondary.tf](../infra/secondary.tf) / [infra/frontdoor.tf](../infra/frontdoor.tf) / [infra/roles.tf](../infra/roles.tf), and per-environment values are in [infra/envs/<env>.tfvars](../infra/envs/). Remote state is stored in the Azure Storage account created by [infra/bootstrap/](../infra/bootstrap/).

### 13.1 Local validation

Before pushing any Terraform change:

```bash
cd infra
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
tflint --recursive --config "$(git rev-parse --show-toplevel)/.tflint.hcl"
```

Catches syntax, type, and lint errors locally — the same checks run in CI.

### 13.2 Plan before deploy

```bash
cd infra
terraform plan -var-file=envs/dev.tfvars -out=tfplan
terraform show -no-color tfplan | less
```

This prints a diff of what `terraform apply` would do. Use it before any production deploy and **always** before changing modules that involve role assignments or CMK. The PR-trigger of [.github/workflows/terraform.yml](../.github/workflows/terraform.yml) posts the plan as a comment automatically.

### 13.3 Best practices for Terraform edits

- Co-locate related resources in a module under [infra/modules/<name>/](../infra/modules) with `main.tf` + `variables.tf` + `outputs.tf` (and `versions.tf` if `azapi` is needed).
- Pass variables in; emit outputs out. Modules should not reach into each other.
- Use the `local.abbrs` map ([infra/locals.tf](../infra/locals.tf), seeded from [infra/abbreviations.json](../infra/abbreviations.json)) for resource-name prefixes.
- Tag every resource by passing `var.tags` (which already includes `azd-env-name` for back-compat plus `azd-service-name` per compute service).
- For role assignments, build `role_definition_id` as `"${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/roleDefinitions/${guid}"` and always set `principal_type` explicitly to avoid eventual-consistency races.
- For Gov-cloud reachability, set `provider "azurerm" { environment = "usgovernment" ... }` in [infra/main.tf](../infra/main.tf) and pass `-backend-config="environment=usgovernment"` to every `terraform init`. See [§15.4 of DEPLOYMENT.md](DEPLOYMENT.md#154-patch-the-workflows-for-gov-cloud).
- For preview API surfaces (Foundry, Search CMK enforcement, Functions FlexConsumption), prefer the `azapi_resource` provider — that's why it's already a required provider in [infra/versions.tf](../infra/versions.tf).

### 13.4 New module workflow

1. Create `infra/modules/<module>/main.tf` + `variables.tf` + `outputs.tf` (+ `versions.tf` if you need `azapi`).
2. Reference it from [infra/primary.tf](../infra/primary.tf) (and from [infra/modules/regional/main.tf](../infra/modules/regional/main.tf) if it must exist in the DR region too) with explicit `module "..."` blocks.
3. If the module produces an identity or endpoint that the apps consume, plumb the output through to the `appservice` / `functions` modules' `app_settings` map.
4. Add the new outputs to [infra/outputs.tf](../infra/outputs.tf) so postprovision/postdeploy scripts and downstream workflows can pick them up.

### 13.5 Touch points to remember

- New data plane → new role assignment in [infra/modules/roleassignments/main.tf](../infra/modules/roleassignments/main.tf).
- New endpoint → new App Service / Function App `app_settings` entry in [infra/primary.tf](../infra/primary.tf) (and the matching DR entry in [infra/modules/regional/main.tf](../infra/modules/regional/main.tf)).
- New variable → declare it in [infra/variables.tf](../infra/variables.tf) and document the default in [infra/envs/dev.tfvars](../infra/envs/dev.tfvars) / [infra/envs/prod.tfvars](../infra/envs/prod.tfvars).

---

## 14. Authentication, authorization, and ACL trimming

### 14.1 Server-side auth

The MCP server validates JWTs on `/mcp` when `Auth:RequireAuthenticatedUser=true`. Validation rules in [Program.cs](../src/DataAiMcp.McpServer/Program.cs):

- Issuer = `https://login.microsoftonline.com/{tenant}/v2.0` (must be `.us` for Gov — see [§5.1 of DEPLOYMENT.md](DEPLOYMENT.md#51-mcp-server-entra-authority)).
- Audience = `Auth:Audience`.
- Token lifetime validated; clock skew = 2 minutes.

### 14.2 Authorization policies

Defined in `Program.cs`:

| Policy | Required claim |
| --- | --- |
| `ReadDocuments` | Authenticated user (default). |
| `QueryStructured` | Authenticated user. |
| `AdminTools` | Authenticated user **and** `roles=DataAiMcp.Admin`. |

To raise the bar on a specific tool, gate the method via a custom `[Authorize(Policy = ...)]` filter or by checking the claim explicitly inside the tool. Today, all three default tool classes (Search/Structured/Metadata) inherit the endpoint-level policy.

### 14.3 ACL trimming

The pieces are in place but not yet end-to-end:

- `IndexDocument.SecurityIds` — populated at ingest time. Currently empty for everything.
- [CallerSecurityContext](../src/DataAiMcp.McpServer/Auth/CallerSecurityContext.cs) — extracts `oid` and `groups` from the caller's JWT into `SecurityIds`.
- [RagOrchestrator.BuildAclFilter](../src/DataAiMcp.McpServer/Rag/RagOrchestrator.cs) — adds `securityIds/any(s: search.in(s, '<csv>'))` to the OData filter.

To turn it on:

1. **At ingest time**, populate `SecurityIds` in `IndexDocument` with the source ACL (SharePoint group GUIDs from Graph, etc.).
2. Confirm `CallerSecurityContext` returns the correct claim names for your token (defaults: `oid`, `groups` — adjust for hash claims).
3. Smoke-test with two users in different groups: each should see only their authorized chunks.

Until that's done, the operating constraint is: **only ingest documents the entire authorized user population is already cleared to read.**

### 14.4 Adding a new role

For a new app-role (e.g., `DataAiMcp.Reader.CombatSystems`):

1. Add the app role to the Entra app registration that defines the audience.
2. Add a policy in `Program.cs`:
   ```csharp
   o.AddPolicy("CombatSystemsReader", p => p.RequireAuthenticatedUser()
       .RequireClaim("roles", "DataAiMcp.Reader.CombatSystems"));
   ```
3. Annotate the relevant tool methods or endpoint mappings.

---

## 15. Telemetry and observability

### 15.1 Sources

- **Trace source**: `DataAiMcp` — defined in [DataAiTelemetry.cs](../src/DataAiMcp.Shared/Telemetry/DataAiTelemetry.cs).
- **Metric meter**: `DataAiMcp` — same file.
- **OpenTelemetry export**: Application Insights via `UseAzureMonitor()` when `APPLICATIONINSIGHTS_CONNECTION_STRING` is set.

### 15.2 Adding an activity

```csharp
using var activity = DataAiTelemetry.ActivitySource.StartActivity("my.operation");
activity?.SetTag("doc.id", documentId);
activity?.SetTag("source", source);
```

The activity automatically becomes a span in App Insights; tags become custom dimensions. **Never set a tag whose value contains user PII or document content.** Tags are queryable and persisted.

### 15.3 Adding a metric

```csharp
public static readonly Histogram<double> MyLatencyMs = DataAiTelemetry.Meter.CreateHistogram<double>("dataaimcp.my.latency.ms");
...
MyLatencyMs.Record((DateTimeOffset.UtcNow - start).TotalMilliseconds);
```

### 15.4 What's instrumented today

- ASP.NET Core HTTP requests (auto).
- Outgoing HttpClient calls (auto).
- `dataaimcp.embedding.latency.ms` — embedding generation duration.
- `dataaimcp.search.latency.ms` — AI Search query duration.
- `ingest.document` activity — one span per blob.
- `RagOrchestrator` info logs include the query, source filter, ACL flag, and hit count.

### 15.5 Recommended additions before production

- `dataaimcp.synapse.query.latency.ms`.
- `dataaimcp.tool.call` counter, dimensioned by tool name.
- A custom event when a generated SQL statement is rejected by the validator.
- A custom event when ACL trimming filters out >0 results (early signal of over-collection).

---

## 16. Testing strategy

### 16.1 Test pyramid

| Layer | Project | Run on every commit | Run pre-release |
| --- | --- | --- | --- |
| Unit | [DataAiMcp.Shared.Tests](../tests/DataAiMcp.Shared.Tests) | Yes | Yes |
| In-process integration | [DataAiMcp.McpServer.Tests](../tests/DataAiMcp.McpServer.Tests) | Yes | Yes |
| Functions integration | [DataAiMcp.Functions.Tests](../tests/DataAiMcp.Functions.Tests) | Yes | Yes |
| End-to-end smoke | [DataAiMcp.Smoke.Tests](../tests/DataAiMcp.Smoke.Tests) | No (requires deployed env) | Yes |

### 16.2 Frameworks

- [xUnit](https://xunit.net/).
- [FluentAssertions](https://fluentassertions.com/) — preferred over `Assert.*`.
- `Microsoft.AspNetCore.Mvc.Testing.WebApplicationFactory<Program>` for in-process integration. See [HealthEndpointTests.cs](../tests/DataAiMcp.McpServer.Tests/HealthEndpointTests.cs) for the canonical setup.

### 16.3 Adding a unit test

```csharp
public sealed class MyFeatureTests
{
    [Fact]
    public void Returns_expected_value_for_known_input()
    {
        var sut = new MyFeature();
        var result = sut.DoThing("input");
        result.Should().Be("expected");
    }
}
```

### 16.4 Adding an MCP-server integration test

```csharp
public sealed class MyToolTests : IClassFixture<McpServerFactory>
{
    private readonly McpServerFactory _factory;
    public MyToolTests(McpServerFactory factory) => _factory = factory;

    [Fact]
    public async Task Tool_responds_with_200()
    {
        using var client = _factory.CreateClient();
        var resp = await client.PostAsync("/mcp", JsonContent.Create(new { /* mcp payload */ }));
        resp.IsSuccessStatusCode.Should().BeTrue();
    }
}
```

`McpServerFactory` overrides configuration to disable auth and supplies dummy endpoints — test code never hits real Azure.

### 16.5 Smoke tests

[DataAiMcp.Smoke.Tests](../tests/DataAiMcp.Smoke.Tests) are run by [infra/scripts/postdeploy.sh](../infra/scripts/postdeploy.sh) after `az webapp deploy`. They:

- Hit `/healthz`.
- Optionally exercise `tools/list` and one `search_documents` call.

Extend smoke tests when adding a tool that has end-to-end side effects.

---

## 17. Branching, commits, code review

### 17.1 Branch strategy

- `main` is always deployable — `cd infra && terraform apply -var-file=envs/prod.tfvars` followed by the `cd.yml` zip deploys should succeed against a fresh subscription from `main`.
- Feature branches: `feature/<short-description>` or `fix/<short-description>`.
- Long-lived environment branches are not used; environments are differentiated by `azd` env name + parameter overrides.

### 17.2 Commit messages

Conventional, imperative subjects:

```
feat(mcp): add lookup_nsn tool against vw_supply_catalog
fix(ingest): handle DocIntel timeout on PDFs > 100 pages
docs(deploy): document Gov-cloud Graph base URL retargeting
```

Body explains *why*, not *what* — diffs already show *what*.

### 17.3 Pull requests

A PR is reviewable when:

- [ ] CI is green ([§18](#18-cicd-pipelines)).
- [ ] Unit tests cover the change.
- [ ] If the change touches `DataAiMcp.Shared`, **all** consumers compile and test green.
- [ ] If the change touches `infra/`, `bicep build` is in CI and the `what-if` was reviewed by a second pair of eyes for any role-assignment or CMK change.
- [ ] Configuration / env-var additions are documented in [docs/DEPLOYMENT.md](DEPLOYMENT.md).
- [ ] Public-API changes in `DataAiMcp.Shared` are called out in the PR description.

---

## 18. CI/CD pipelines

### 18.1 CI ([.github/workflows/ci.yml](../.github/workflows/ci.yml))

On every push and PR:

1. `dotnet restore`.
2. `dotnet build -c Release` — fails on any warning (treat-warnings-as-errors).
3. `dotnet test -c Release --no-build`.
4. `terraform fmt -check -recursive`, `terraform validate`, and `tflint --recursive` for `infra/`.

### 18.2 CD ([.github/workflows/cd.yml](../.github/workflows/cd.yml))

OIDC-federated against the deployment subscription:

1. `azure/login@v2` (must use `environment: AzureUSGovernment` for Gov).
2. `terraform apply -var-file=envs/<env>.tfvars`.
3. The §11 zip-deploy steps (or let the `cd.yml` workflow run automatically).

When changing the workflow, test against a non-production environment first. The OIDC trust relationship requires the federated credential subject claim to match `repo:<org>/<repo>:environment:<env-name>` — adding a new environment requires a new federated credential.

### 18.3 Adding a new test project to CI

The CI workflow runs `dotnet test DataAiMcp.slnx`, so any test project added to the solution is automatically picked up. Add the project to [DataAiMcp.slnx](../DataAiMcp.slnx) and CI runs it.

---

## 19. Performance tuning

### 19.1 Search latency

- HNSW parameters in [SearchIndexSchema.cs](../src/DataAiMcp.Shared/Search/SearchIndexSchema.cs): `M=4, EfConstruction=400, EfSearch=500`. Bump `EfSearch` for higher recall at the cost of latency.
- `KNearestNeighborsCount = Math.Max(top, 50)` in `RagOrchestrator` — increase for better recall on large-`top` queries.
- Semantic reranker is on by default (`QueryType = SearchQueryType.Semantic`). Disable for non-natural-language queries to drop a hop.

### 19.2 Ingestion throughput

- Document Intelligence is the slowest stage. Watch its 429s in App Insights.
- Embedding generation is batched per chunk today. For corpora with many small chunks, batch the embedding calls (the `Microsoft.Extensions.AI` API supports batched generate).
- AI Search index writes are upsert-by-ID; batched writes via `IIndexWriter` are already in place. Confirm batch size matches your data shape (default ~100 docs).

### 19.3 Foundry token spend

- The biggest cost lever is the embedding model and the chat model used for `query_structured_data`.
- Set Foundry diagnostic settings → Log Analytics ([§16.2 of DEPLOYMENT.md](DEPLOYMENT.md#162-cost--token-telemetry)).
- Set a cost alert on the Foundry account. Alert at 50%, 80%, 100% of the monthly budget.

### 19.4 App Service plan sizing

- B1 is fine for a single department POC.
- For production, P1v3 minimum — required for VNet integration with Private Endpoints and for autoscale. Override via `AZURE_APP_SERVICE_PLAN_SKU`.

### 19.5 Synapse query timeout

- `Synapse:QueryTimeoutSeconds` defaults to 30. Increase for genuinely large analytical queries; drop for an interactive RAG pattern where the user expects sub-second.

---

## 20. Security and supply chain

### 20.1 NuGet packages

- Centralized in [Directory.Packages.props](../Directory.Packages.props). Add new versions there, never inline in a `.csproj`.
- Pin to specific versions; avoid floating wildcards.
- Run `dotnet list package --vulnerable --include-transitive` periodically. CI does not run this today — consider adding it.

### 20.2 Secret hygiene

- Never check in connection strings, keys, certificates, or tokens.
- `local.settings.json` (Functions) is `.gitignore`d. The template lives in [local.settings.template.json](../src/DataAiMcp.Ingestion.Functions/local.settings.template.json).
- All secrets in production come from Key Vault references in App Service / Function App settings.

### 20.3 SQL injection

- `query_structured_data` produces SQL via an LLM. The defenses are: a strict prompt in `SqlGenerator`, **and** server-side validation in `SynapseQueryClient`. Neither alone is sufficient. Both must be maintained whenever the prompt or the executor changes.
- For any tool that takes user input and composes a query (e.g., the `lookup_nsn` example in [§7.2](#72-step-by-step--adding-lookup_nsn)), use parameterized queries. The example above interpolates a string — that's deliberately the *wrong* pattern shown for explanatory purposes; replace with `SqlParameter` in production code.

### 20.4 Token caching

- `DefaultAzureCredential` caches tokens internally. Do not wrap it in your own cache.
- Any custom `TokenCredential` subclass must respect the credential abstraction's lifetime semantics. Don't write one unless you have to.

### 20.5 OWASP awareness

The codebase has been written with OWASP Top 10 in mind:

- **Injection** — SQL generated by the LLM is constrained at two layers; tools that compose SQL or OData filters escape user input (`Replace("'", "''")`).
- **Broken auth** — JWT validation with full audience/issuer/lifetime checks.
- **Sensitive data exposure** — TLS in transit, KMS at rest, optional CMK.
- **Insecure deserialization** — System.Text.Json with explicit property names; no BinaryFormatter.
- **Insufficient logging** — App Insights end-to-end.

When you add code, hold the bar.

---

## 21. Common development tasks — recipes

### 21.1 Add a new App Service environment variable

1. Add to [appsettings.json](../src/DataAiMcp.McpServer/appsettings.json) with a sensible default.
2. Bind via `IOptions<T>`.
3. If sourced from infra, pipe through [infra/primary.tf](../infra/primary.tf) `appSettings`.
4. Update [docs/DEPLOYMENT.md](DEPLOYMENT.md) reference table.

### 21.2 Run a single integration test in isolation

```bash
dotnet test tests/DataAiMcp.McpServer.Tests --filter "FullyQualifiedName~Healthz_returnsOk"
```

### 21.3 Replay an ingestion failure

1. Find the original blob in `landing/` (or in the failed-ingestion DLQ, if one is configured).
2. Re-upload it with a slightly different name to retrigger the function:
   ```bash
   az storage blob upload --account-name ... --container-name landing --name pilot/sample.replay.pdf --file ./local.pdf --auth-mode login
   ```
3. Watch logs:
   ```bash
   az functionapp log tail -n $FUNC -g $RG
   ```

### 21.4 Drop and rebuild the search index

```bash
SEARCH_NAME=$(terraform -chdir=infra output -raw SEARCH_NAME)
RG=$(terraform -chdir=infra output -raw AZURE_RESOURCE_GROUP)

az search index delete --service-name "$SEARCH_NAME" --resource-group "$RG" --name documents

dotnet run --project src/DataAiMcp.Tools.IndexProvisioner
```

Then re-ingest.

### 21.5 Test ACL trimming end-to-end

1. Pick two test users in different Entra groups.
2. Manually populate `SecurityIds` on a pilot document with each user's group GUID.
3. Sign in as each user, mint a token, call `search_documents`. Confirm each user only sees the chunks tagged with their group.

---

## 22. Pitfalls specific to development

These are the *development* pitfalls — for *deployment* and *operational* pitfalls see [docs/README.md](README.md#pitfalls--read-this-section-twice) and [docs/DEPLOYMENT.md §17](DEPLOYMENT.md#17-troubleshooting).

1. **Treat-warnings-as-errors surprises.** A new analyzer rule introduced by an SDK update can fail a previously-green build. When that happens, fix the root cause, don't add to `NoWarn`.

2. **Public API breakage in `DataAiMcp.Shared`.** Renaming a property in `IndexDocument` will compile-break the IndexProvisioner and the MCP server simultaneously. Always run a full-solution build.

3. **Forgetting to register a new tool class.** `[McpServerToolType]` attribute alone is not enough — you must also call `WithTools<T>()` in `Program.cs`. The build will succeed; the tool just won't appear in `tools/list`.

4. **Forgetting to plumb a new env var through Bicep.** A change in `appsettings.json` works locally and looks fine in CI but reads as null in the deployed App Service. Always verify `az webapp config appsettings list` after deploy.

5. **Synapse view referencing a column that doesn't exist in the parquet.** The view creates fine; queries error at runtime. Validate the view via `SELECT TOP 1 * FROM dbo.<view>` before declaring the dataset done.

6. **Embedding dimension drift.** Updating `EmbeddingDimensions` without re-creating the index produces "vector dimension mismatch" errors at query time. The index is the source of truth — re-create it.

7. **Token validation skew.** Setting `Auth:RequireAuthenticatedUser=true` locally without the right tenant/audience = 401 with no helpful message. For local dev, leave auth off.

8. **Functions cold start during smoke test.** The smoke test runs immediately after the Function App zip deploy. The first MCP request can take several seconds. The smoke project tolerates one-shot retries; if you change the smoke flow, preserve the retry.

9. **Local Functions reaching real Azure.** `func start` will happily make calls against a real Azure environment. Make sure the `AZURE_*` env vars in `local.settings.json` point where you expect — easy to accidentally write to a production storage account.

10. **CMK keys on tear-down.** Do not run `terraform destroy` against any environment with CMK enabled unless you have already exported the keys you care about, and do **not** subsequently `az keyvault purge` the soft-deleted vault — that removes the encryption keys that the storage / search service still references during their own soft-delete window.

---

## Appendix A — File-by-file extension map

When you need to extend in a specific direction, this is the file you start at.

| Goal | Primary file | Secondary touch points |
| --- | --- | --- |
| Add a new MCP tool | New file in [src/DataAiMcp.McpServer/Tools/](../src/DataAiMcp.McpServer/Tools) | [Program.cs](../src/DataAiMcp.McpServer/Program.cs) `WithTools<T>()`, tests |
| Add a new ingestion source (push) | New JSON in [infra/datafactory/pipelines/](../infra/datafactory/pipelines) | None (auto via `landing/` blob trigger) |
| Add a new ingestion source (pull) | New file in [src/DataAiMcp.Ingestion.Functions/](../src/DataAiMcp.Ingestion.Functions) | [Program.cs](../src/DataAiMcp.Ingestion.Functions/Program.cs) DI, [appsettings.json](../src/DataAiMcp.McpServer/appsettings.json) `Sources` |
| Add a structured dataset | New SQL in [infra/synapse/views/](../infra/synapse/views) | [appsettings.json](../src/DataAiMcp.McpServer/appsettings.json) `Datasets` |
| Change embedding model | [infra/envs/<env>.tfvars](../infra/envs/) `embedding_deployment` (or [foundry/main.tf](../infra/modules/foundry/main.tf) for SKU) | [SearchIndexSchema.cs](../src/DataAiMcp.Shared/Search/SearchIndexSchema.cs) `EmbeddingDimensions` |
| Change chat model | [infra/envs/<env>.tfvars](../infra/envs/) `chat_deployment` | App settings `Foundry:ChatDeployment` |
| Change chunker behavior | [MarkdownChunker.cs](../src/DataAiMcp.Shared/Documents/MarkdownChunker.cs) | [SharedServiceCollectionExtensions.cs](../src/DataAiMcp.Shared/DependencyInjection/SharedServiceCollectionExtensions.cs) options binding |
| Change schema | [SearchIndexSchema.cs](../src/DataAiMcp.Shared/Search/SearchIndexSchema.cs) | [Models.cs](../src/DataAiMcp.Shared/Models/Models.cs), [tests/DataAiMcp.Shared.Tests/SearchIndexSchemaTests.cs](../tests/DataAiMcp.Shared.Tests/SearchIndexSchemaTests.cs) |
| Add a new role-based policy | [Program.cs](../src/DataAiMcp.McpServer/Program.cs) | [McpPolicies.cs](../src/DataAiMcp.McpServer/Auth/McpPolicies.cs) |
| Tighten / change auth | [Program.cs](../src/DataAiMcp.McpServer/Program.cs) | [McpAuthOptions.cs](../src/DataAiMcp.McpServer/Auth/McpAuthOptions.cs) |
| Add a metric or trace | [DataAiTelemetry.cs](../src/DataAiMcp.Shared/Telemetry/DataAiTelemetry.cs) | Call site |
| Add an Azure resource | new module under [infra/modules/](../infra/modules) | [infra/primary.tf](../infra/primary.tf), [infra/modules/roleassignments/main.tf](../infra/modules/roleassignments/main.tf), [infra/outputs.tf](../infra/outputs.tf), App Service / Function App `app_settings` |

---

## Appendix B — Definition of Done checklist

Use this for every non-trivial change before opening a PR.

### Code

- [ ] Builds clean with `TreatWarningsAsErrors=true` for the entire solution.
- [ ] All existing tests pass.
- [ ] New code has unit tests where applicable.
- [ ] Public-API changes to `DataAiMcp.Shared` are called out in the PR.
- [ ] No new `#pragma warning disable` without an accompanying comment.

### Configuration

- [ ] New configuration values have defaults in `appsettings.json`.
- [ ] Required production values are surfaced as Bicep outputs and wired through to App Service / Function App settings.
- [ ] [docs/DEPLOYMENT.md](DEPLOYMENT.md) reference tables updated.

### Infrastructure

- [ ] `az bicep build` succeeds.
- [ ] `az deployment sub what-if` reviewed for any role-assignment or CMK change.
- [ ] New role assignments scoped narrowly (specific resource, not subscription).
- [ ] Sovereign-cloud assumptions preserved (no `.com` literals where `environment().suffixes.*` should be used).

### Documentation

- [ ] [docs/README.md](README.md) updated if user-visible surface changed.
- [ ] [docs/DEPLOYMENT.md](DEPLOYMENT.md) updated if operator workflow changed.
- [ ] This file ([docs/DEVELOPMENT.md](DEVELOPMENT.md)) updated if extension patterns changed.
- [ ] [README.md](../README.md) updated if quickstart commands changed.

### Security

- [ ] No secrets committed.
- [ ] User input that flows into SQL or OData filters is parameterized or escaped.
- [ ] New tools that compose untrusted strings have a corresponding validator.
- [ ] OWASP Top 10 review for the change.

### Operational

- [ ] Telemetry added for new code paths.
- [ ] Failure modes have clear log messages.
- [ ] Backwards-compat noted for breaking schema/config changes.
- [ ] Tear-down behavior verified (no resource leaks on `terraform destroy` followed by `az keyvault purge` / `az cognitiveservices account purge`).

Sign off only when every applicable box is checked.

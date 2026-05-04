# Adding a new source type

> Developer cookbook for extending the platform with a brand-new ingestion source. For onboarding an existing connector to a new tenant, see the per-source pages under [`docs/ingestion/`](.).
>
> See the [Ingestion hub](../INGESTION.md) for cross-cutting concepts.

## Decision tree

```
Q1: Is the data binary documents (PDF, DOCX, etc.) or structured rows (DB, CSV)?
    │
    ├─ Binary documents
    │     │
    │     Q2: Is there an existing connector that fits (Graph drive, AFS, blob drop)?
    │     │
    │     ├─ Yes → use the existing path; just configure it
    │     │
    │     └─ No → Q3: Does the source have a streaming / event API?
    │              │
    │              ├─ Yes → Function with EventGrid/Webhook trigger (e.g., Box webhooks)
    │              │
    │              └─ No → Function with Timer trigger (poll on schedule)
    │
    └─ Structured rows
          │
          Q4: Is there a first-class ADF connector?
          │
          ├─ Yes → ADF pipeline, Parquet to raw/<source>/, Synapse view
          │
          └─ No → Q5: Can a Function plus a generated Parquet writer handle it?
                  │
                  ├─ Yes → Function that writes Parquet directly to raw/<source>/
                  │
                  └─ No → Pre-stage to AFS / SQL MI and use those connectors
```

## Function pattern (binary RAG path)

Minimum new code: one Function class and one DI registration.

### 1. Skeleton class

```csharp
// src/DataAiMcp.Ingestion.Functions/MyNewSourceFunction.cs
using DataAiMcp.Shared.Telemetry;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

public sealed class MyNewSourceFunction
{
    private readonly IMyNewSourceFetcher _fetcher;
    private readonly MyNewSourceOptions _options;
    private readonly ILogger<MyNewSourceFunction> _logger;

    public MyNewSourceFunction(
        IMyNewSourceFetcher fetcher,
        IOptions<MyNewSourceOptions> options,
        ILogger<MyNewSourceFunction> logger)
    {
        _fetcher = fetcher;
        _options = options.Value;
        _logger = logger;
    }

    [Function(nameof(MyNewSourceFunction))]
    public async Task RunAsync(
        [TimerTrigger("%MyNewSource:Schedule%")] TimerInfo timer,
        CancellationToken ct)
    {
        using var span = DataAiTelemetry.ActivitySource.StartActivity(nameof(MyNewSourceFunction));
        span?.SetTag("source", "mynewsource");

        foreach (var item in _options.Items)
        {
            await foreach (var file in _fetcher.EnumerateAsync(item, ct))
            {
                // Upload to landing/mynewsource/<path>
                // Set blob metadata securityIds appropriately
            }
        }
    }
}
```

### 2. Options class (mirror `GraphOptions` shape)

```csharp
public sealed class MyNewSourceOptions
{
    public string Schedule { get; init; } = "0 0 */6 * * *";
    public List<string> Items { get; init; } = new();
}
```

### 3. DI registration in `Program.cs`

```csharp
builder.Services.Configure<MyNewSourceOptions>(
    builder.Configuration.GetSection("MyNewSource"));
builder.Services.AddSingleton<IMyNewSourceFetcher, MyNewSourceFetcher>();
```

### 4. Honor `securityIds`

Resolve per-file ACLs to AAD object IDs and set them as blob metadata. **Fail-closed** — if your fetcher can't resolve the ACL, write `[]`, not `["__org__"]`. Look at [`GraphFileFetcher.ResolveSecurityIdsAsync`](../../src/DataAiMcp.Ingestion.Functions/Graph/GraphFileFetcher.cs) for the pattern.

```csharp
var securityIds = await _fetcher.ResolveSecurityIdsAsync(file, ct);
var metadata = new Dictionary<string, string>
{
    ["securityIds"] = JsonSerializer.Serialize(securityIds),
};
await blobClient.UploadAsync(stream, new BlobUploadOptions { Metadata = metadata }, ct);
```

### 5. Tests

Add a smoke test analogous to [`tests/DataAiMcp.Functions.Tests/IngestionPipelineSmokeTests.cs`](../../tests/DataAiMcp.Functions.Tests/IngestionPipelineSmokeTests.cs). Use the in-memory `Microsoft.Azure.Functions.Worker.Testing` patterns.

## ADF pattern (structured path)

### 1. Pipeline JSON

Create `infra/datafactory/pipelines/pl_mynewsource_to_adls.json` following the shape of [`pl_sql_mi_to_adls.json`](../../infra/datafactory/pipelines/pl_sql_mi_to_adls.json). Required activities: a Copy that writes to `raw/mynewsource/<key>/<run-id>.parquet`.

### 2. New module file

Create `infra/modules/datafactory/mynewsource.tf` with:

- A `azurerm_data_factory_linked_custom_service "mynewsource"` (gated on whatever required tfvar makes the source "configured")
- A `azurerm_data_factory_custom_dataset "mynewsource_*"` per dataset shape
- An `azapi_resource "mynewsource_pipeline"` reading the JSON from §1

> Why `azapi_resource` and not `azurerm_data_factory_pipeline`? The `azurerm_data_factory_pipeline.parameters` argument is `map(string)` and can't carry array-of-object pipeline parameters. See `sqlmi.tf` for a working example.

### 3. Tfvars

Add new variables to:
- `infra/modules/datafactory/variables.tf`
- `infra/variables.tf` (forwarded with the same name)
- `infra/envs/dev.tfvars` and `prod.tfvars` (commented-out template block)
- The new `module "datafactory"` block in `infra/primary.tf`

### 4. Trigger

Add an `azurerm_data_factory_trigger_schedule` to `infra/modules/datafactory/triggers.tf`. Use the existing pattern: parse `var.mynewsource_schedule_cron` via `split(" ", cron)[2]` for hour and `[1]` for minute (6-field Quartz/Spring cron).

### 5. Synapse view

Add a SQL DDL file to `infra/synapse/views/` that opens an external table over `curated/mynewsource/`. The view becomes available as a Synapse serverless query target for MCP tools.

## Updating `SearchIndexSchema`

If your source needs new fields on the AI Search index (e.g., a `tags` array or a domain-specific filter field), edit [`src/DataAiMcp.Shared/Search/SearchIndexSchema.cs`](../../src/DataAiMcp.Shared/Search/SearchIndexSchema.cs) and rerun the index provisioner:

```bash
dotnet run --project src/DataAiMcp.Tools.IndexProvisioner -- \
  --search-endpoint https://<search>.search.windows.net --recreate
```

> `--recreate` drops and rebuilds the index. For a non-destructive add of a single nullable field, use `--update` instead (does in-place schema migration).

## Telemetry tags

Tag every span you start with `source = "<your-source>"` so the existing dashboards and the [`search_ingestion_latency`](../../infra/modules/alerts/main.tf) alert keep working:

```csharp
using var activity = DataAiTelemetry.ActivitySource.StartActivity(nameof(MyNewSourceFunction));
activity?.SetTag("source", "mynewsource");
```

For metrics, prefer adding a `source` tag to existing histograms over creating new metric names:

```csharp
DataAiTelemetry.IndexLatencyMs.Record(elapsed,
    new KeyValuePair<string, object?>("source", "mynewsource"));
```

## Documentation

After your code lands, **add a new cookbook**: copy the template from any of [`sharepoint-files.md`](sharepoint-files.md), [`azure-file-share.md`](azure-file-share.md), etc., and fill in:

- What the source provides (data shape, examples)
- Architecture (ASCII data-flow block — keep parity with the rest of the docs)
- Required Azure resources & permissions
- Configuration keys
- Step-by-step onboarding
- Verification commands
- Troubleshooting matrix
- Limits and scaling
- Sovereign-cloud notes

Then update the per-source matrix in [the Ingestion hub §7](../INGESTION.md#7-per-source-matrix).

## Checklist

- [ ] Function or pipeline JSON
- [ ] Options class + DI registration / tfvars + module file
- [ ] `securityIds` honored (binary path) or ACL-caveat documented (structured path)
- [ ] Telemetry tagged with `source`
- [ ] Smoke test added
- [ ] Cookbook page added under [`docs/ingestion/`](.)
- [ ] Hub matrix updated ([`docs/INGESTION.md`](../INGESTION.md))
- [ ] If structured: linked `> [!WARNING]` to [§5.1](../INGESTION.md#51-why-structured-queries-dont-enforce-securityids) at the top of the cookbook
- [ ] If KV-stored secret: rotation cadence documented in [secret-rotation.md](secret-rotation.md)

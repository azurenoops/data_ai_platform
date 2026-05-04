using DataAiMcp.Shared.Storage;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace DataAiMcp.Ingestion.Functions;

/// <summary>
/// Promotes blobs landed in <c>raw/</c> (e.g. ADF Parquet drops from SQL MI / Azure Files / Dataverse Synapse-Link sinks)
/// into the <c>curated/</c> filesystem with consistent naming. The companion Synapse views read from <c>curated/</c>.
/// </summary>
public sealed class CurationFunction
{
    private readonly IDataLakeRepository _lake;
    private readonly ILogger<CurationFunction> _logger;

    public CurationFunction(IDataLakeRepository lake, ILogger<CurationFunction> logger)
    {
        _lake = lake;
        _logger = logger;
    }

    [Function("CurateRawDrop")]
    public async Task RunAsync(
        [BlobTrigger("raw/{name}", Source = BlobTriggerSource.EventGrid, Connection = "AzureWebJobsStorage")]
        Stream content,
        string name,
        CancellationToken cancellationToken)
    {
        if (!name.EndsWith(".parquet", StringComparison.OrdinalIgnoreCase))
        {
            _logger.LogDebug("Skipping non-parquet raw drop {Blob}.", name);
            return;
        }

        var curatedPath = name; // 1:1 path mapping; consumers can rely on stable layout
        await _lake.UploadAsync(
            StorageContainer.Curated,
            curatedPath,
            content,
            contentType: "application/octet-stream",
            metadata: null,
            cancellationToken: cancellationToken).ConfigureAwait(false);

        _logger.LogInformation("Curated raw drop {Blob} -> curated/{Path}.", name, curatedPath);
    }
}

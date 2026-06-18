using System.Text.Json;
using Azure.Messaging;
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
        [EventGridTrigger] CloudEvent cloudEvent,
        CancellationToken cancellationToken)
    {
        // Parse Event Grid cloud event to extract blob name
        try
        {
            if (cloudEvent.Data == null)
            {
                _logger.LogWarning("Event Grid message data is null.");
                return;
            }

            // Deserialize BinaryData to JsonElement
            var jsonElement = JsonSerializer.Deserialize<JsonElement>(cloudEvent.Data.ToString());

            if (!jsonElement.TryGetProperty("url", out var urlElement))
            {
                _logger.LogWarning("Event Grid message missing 'url' property.");
                return;
            }

            var blobUrl = urlElement.GetString();
            if (string.IsNullOrEmpty(blobUrl))
            {
                _logger.LogWarning("Event Grid message has empty 'url'.");
                return;
            }

            // Extract blob name from URL: https://account.blob.core.windows.net/raw/file.parquet → raw/file.parquet
            var uri = new Uri(blobUrl);
            var path = uri.AbsolutePath.TrimStart('/');
            var segments = path.Split('/', 2);
            if (segments.Length < 2 || segments[0] != "raw")
            {
                _logger.LogDebug("Skipping non-raw container blob {Path}.", path);
                return;
            }

            var name = segments[1];

            if (!name.EndsWith(".parquet", StringComparison.OrdinalIgnoreCase))
            {
                _logger.LogDebug("Skipping non-parquet raw drop {Blob}.", name);
                return;
            }

            _logger.LogInformation("CurateRawDrop triggered from Event Grid for {Blob}.", name);

            // Download blob to stream and curate
            using var content = await _lake.OpenReadAsync(StorageContainer.Raw, name, cancellationToken).ConfigureAwait(false);

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
        catch (Exception ex)
        {
            _logger.LogError(ex, "CurateRawDrop failed.");
            throw;
        }
    }
}

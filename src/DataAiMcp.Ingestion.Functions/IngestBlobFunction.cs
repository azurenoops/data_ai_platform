using System.Text.Json;
using Azure.Messaging;
using DataAiMcp.Ingestion.Functions.Pipeline;
using DataAiMcp.Shared.Storage;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace DataAiMcp.Ingestion.Functions;

/// <summary>
/// Event Grid-triggered ingestion: any blob landing in the <c>landing</c> container fires an event that is
/// run through the document pipeline (DI → chunk → embed → AI Search upsert).
/// </summary>
public sealed class IngestBlobFunction
{
    private readonly DocumentIngestionPipeline _pipeline;
    private readonly IDataLakeRepository _lake;
    private readonly ILogger<IngestBlobFunction> _logger;

    public IngestBlobFunction(DocumentIngestionPipeline pipeline, IDataLakeRepository lake, ILogger<IngestBlobFunction> logger)
    {
        _pipeline = pipeline;
        _lake = lake;
        _logger = logger;
    }

    [Function("IngestBlob")]
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

            // Extract blob name from URL: https://account.blob.core.windows.net/landing/file.pdf → landing/file.pdf
            var uri = new Uri(blobUrl);
            var path = uri.AbsolutePath.TrimStart('/');
            var segments = path.Split('/', 2);
            if (segments.Length < 2 || segments[0] != "landing")
            {
                _logger.LogWarning("Invalid blob path {Path}; expected landing/file.", path);
                return;
            }

            var name = segments[1];
            _logger.LogInformation("IngestBlob triggered from Event Grid for {Blob}.", name);

            // Download blob to stream
            using var content = await _lake.OpenReadAsync(StorageContainer.Landing, name, cancellationToken).ConfigureAwait(false);
            _logger.LogInformation("IngestBlob ingesting {Blob}.", name);
            await _pipeline.IngestAsync(name, content, blobMetadata: null, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "IngestBlob failed.");
            throw;
        }
    }
}

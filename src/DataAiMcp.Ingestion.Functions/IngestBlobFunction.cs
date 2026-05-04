using DataAiMcp.Ingestion.Functions.Pipeline;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace DataAiMcp.Ingestion.Functions;

/// <summary>
/// Blob-trigger ingestion: any blob landing in the <c>landing</c> container is run through
/// the document pipeline (DI → chunk → embed → AI Search upsert).
/// </summary>
public sealed class IngestBlobFunction
{
    private readonly DocumentIngestionPipeline _pipeline;
    private readonly ILogger<IngestBlobFunction> _logger;

    public IngestBlobFunction(DocumentIngestionPipeline pipeline, ILogger<IngestBlobFunction> logger)
    {
        _pipeline = pipeline;
        _logger = logger;
    }

    [Function("IngestBlob")]
    public async Task RunAsync(
        [BlobTrigger("landing/{name}", Source = BlobTriggerSource.EventGrid, Connection = "AzureWebJobsStorage")]
        Stream content,
        string name,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("IngestBlob fired for {Blob} ({Bytes} bytes).", name, content.Length);
        await _pipeline.IngestAsync(name, content, blobMetadata: null, cancellationToken).ConfigureAwait(false);
    }
}

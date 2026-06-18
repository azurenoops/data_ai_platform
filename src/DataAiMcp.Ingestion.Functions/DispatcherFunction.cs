using DataAiMcp.Shared.Ingestion;
using DataAiMcp.Shared.Storage;
using DataAiMcp.Shared.Telemetry;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace DataAiMcp.Ingestion.Functions;

/// <summary>
/// Dispatcher function that runs on a schedule and processes all enabled source configurations.
/// Reads from CosmosDB, invokes the appropriate fetcher for each source, and uploads to landing/.
/// This is the single timer entrypoint for connector ingestion.
/// </summary>
public sealed class DispatcherFunction
{
    private readonly ISourceConfigurationStore _configStore;
    private readonly ISourceFetcherFactory _fetcherFactory;
    private readonly IDataLakeRepository _storage;
    private readonly ILogger<DispatcherFunction> _logger;

    public DispatcherFunction(
        ISourceConfigurationStore configStore,
        ISourceFetcherFactory fetcherFactory,
        IDataLakeRepository storage,
        ILogger<DispatcherFunction> logger)
    {
        _configStore = configStore;
        _fetcherFactory = fetcherFactory;
        _storage = storage;
        _logger = logger;
    }

    [Function("DispatcherFunction")]
    public async Task RunAsync(
        [TimerTrigger("0 0 */6 * * *")] TimerInfo timer,
        CancellationToken cancellationToken)
    {
        using var activity = DataAiTelemetry.ActivitySource.StartActivity(nameof(DispatcherFunction));
        activity?.SetTag("function", "dispatcher");

        _logger.LogInformation("DispatcherFunction started at {UtcNow}", DateTime.UtcNow);

        try
        {
            var sources = (await _configStore.GetEnabledSourcesAsync(cancellationToken)).ToList();
            _logger.LogInformation("Processing {SourceCount} enabled sources", sources.Count);

            foreach (var source in sources)
            {
                await ProcessSourceAsync(source, cancellationToken);
            }

            _logger.LogInformation("DispatcherFunction completed successfully");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "DispatcherFunction failed");
            activity?.SetStatus(System.Diagnostics.ActivityStatusCode.Error, ex.Message);
            throw;
        }
    }

    private async Task ProcessSourceAsync(SourceConfiguration source, CancellationToken cancellationToken)
    {
        using var activity = DataAiTelemetry.ActivitySource.StartActivity("ProcessSource");
        activity?.SetTag("sourceId", source.Id);
        activity?.SetTag("sourceType", source.SourceType);

        try
        {
            _logger.LogInformation("Processing source {SourceId} ({SourceType})", source.Id, source.SourceType);

            var fetcher = _fetcherFactory.CreateFetcher(source.SourceType);
            var itemCount = 0;

            await foreach (var (path, stream, securityIds) in fetcher.EnumerateAsync(source.Settings, cancellationToken))
            {
                try
                {
                    var blobPath = $"{source.SourceType.ToLowerInvariant()}/{source.Id}/{path}";
                    
                    // Check if already exists (skip duplicates)
                    if (await _storage.ExistsAsync(StorageContainer.Landing, blobPath, cancellationToken))
                    {
                        _logger.LogDebug("Blob already exists: {BlobPath}", blobPath);
                        continue;
                    }

                    var metadata = new Dictionary<string, string>(StringComparer.Ordinal)
                    {
                        ["source"] = source.SourceType,
                        ["sourceId"] = source.Id,
                        ["securityIds"] = securityIds,
                        ["ingestedAt"] = DateTime.UtcNow.ToString("O"),
                    };

                    await _storage.UploadAsync(
                        StorageContainer.Landing,
                        blobPath,
                        stream,
                        contentType: null,
                        metadata: metadata,
                        cancellationToken: cancellationToken);

                    itemCount++;
                    _logger.LogDebug("Uploaded blob: {BlobPath}", blobPath);
                }
                finally
                {
                    await stream.DisposeAsync();
                }
            }

            _logger.LogInformation("Source {SourceId}: processed {ItemCount} items", source.Id, itemCount);
            await _configStore.UpdateLastRunAsync(source.Id, itemCount, success: true, errorMessage: null, cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to process source {SourceId}", source.Id);
            await _configStore.UpdateLastRunAsync(source.Id, 0, success: false, errorMessage: ex.Message, cancellationToken);
            activity?.SetStatus(System.Diagnostics.ActivityStatusCode.Error, ex.Message);
            // Continue with next source instead of failing the entire run
        }
    }
}

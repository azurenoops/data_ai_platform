using Azure;
using Azure.Search.Documents;
using Azure.Search.Documents.Models;
using DataAiMcp.Shared.Auth;
using DataAiMcp.Shared.Models;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace DataAiMcp.Shared.Search;

/// <summary>
/// Abstraction over Search write paths so a single-region deployment can use a direct <see cref="SearchClient"/>,
/// and a multi-region DR deployment can fan out the same write to both regional indexes.
/// </summary>
public interface IIndexWriter
{
    Task<Response<IndexDocumentsResult>> IndexDocumentsAsync(
        IndexDocumentsBatch<IndexDocument> batch,
        IndexDocumentsOptions? options = null,
        CancellationToken cancellationToken = default);
}

/// <summary>Single-region writer: forwards directly to one <see cref="SearchClient"/>.</summary>
public sealed class SingleSearchIndexWriter : IIndexWriter
{
    private readonly SearchClient _client;

    public SingleSearchIndexWriter(SearchClient client)
    {
        _client = client;
    }

    public Task<Response<IndexDocumentsResult>> IndexDocumentsAsync(
        IndexDocumentsBatch<IndexDocument> batch,
        IndexDocumentsOptions? options = null,
        CancellationToken cancellationToken = default)
        => _client.IndexDocumentsAsync(batch, options, cancellationToken);
}

/// <summary>
/// Dual-region writer: writes to primary first, then to secondary in parallel.
/// Primary failure throws. Secondary failure is logged but does not fail the request -
/// secondary will be eventually-reconciled by a periodic reindex job.
/// </summary>
public sealed class DualWriteSearchIndexWriter : IIndexWriter
{
    private readonly SearchClient _primary;
    private readonly SearchClient _secondary;
    private readonly ILogger<DualWriteSearchIndexWriter> _logger;

    public DualWriteSearchIndexWriter(
        SearchClient primary,
        SearchClient secondary,
        ILogger<DualWriteSearchIndexWriter> logger)
    {
        _primary = primary;
        _secondary = secondary;
        _logger = logger;
    }

    public async Task<Response<IndexDocumentsResult>> IndexDocumentsAsync(
        IndexDocumentsBatch<IndexDocument> batch,
        IndexDocumentsOptions? options = null,
        CancellationToken cancellationToken = default)
    {
        // Kick off both in parallel - primary success is what we return; secondary is best-effort.
        var primaryTask = _primary.IndexDocumentsAsync(batch, options, cancellationToken);
        var secondaryTask = _secondary.IndexDocumentsAsync(batch, options, cancellationToken);

        Response<IndexDocumentsResult> primaryResponse;
        try
        {
            primaryResponse = await primaryTask.ConfigureAwait(false);
        }
        catch
        {
            // If primary fails we still observe secondary so we don't leave a hung task.
            try { await secondaryTask.ConfigureAwait(false); } catch { /* swallow - primary takes precedence */ }
            throw;
        }

        try
        {
            await secondaryTask.ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(
                ex,
                "Secondary-region index write failed - primary succeeded; periodic reconciliation will catch the drift.");
        }

        return primaryResponse;
    }

    /// <summary>
    /// DI helper that builds a dual-write writer when SecondaryEndpoint is configured, falling back to single.
    /// </summary>
    public static IIndexWriter Create(
        AzureCredentialFactory credentialFactory,
        IOptions<SearchOptions> options,
        ILoggerFactory loggerFactory)
    {
        var opts = options.Value;
        var primary = new SearchClient(new Uri(opts.Endpoint), opts.IndexName, credentialFactory.Credential);

        if (string.IsNullOrWhiteSpace(opts.SecondaryEndpoint))
        {
            return new SingleSearchIndexWriter(primary);
        }

        var secondary = new SearchClient(new Uri(opts.SecondaryEndpoint), opts.IndexName, credentialFactory.Credential);
        return new DualWriteSearchIndexWriter(primary, secondary, loggerFactory.CreateLogger<DualWriteSearchIndexWriter>());
    }
}

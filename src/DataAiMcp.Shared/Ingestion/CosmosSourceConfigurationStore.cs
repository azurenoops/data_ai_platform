using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Cosmos.Linq;
using Microsoft.Extensions.Logging;

namespace DataAiMcp.Shared.Ingestion;

/// <summary>
/// CosmosDB implementation of source configuration store.
/// Uses a "source-configurations" container with partitioning by sourceType.
/// </summary>
public sealed class CosmosSourceConfigurationStore : ISourceConfigurationStore
{
    private readonly Container _container;
    private readonly ILogger<CosmosSourceConfigurationStore> _logger;

    public CosmosSourceConfigurationStore(
        Container container,
        ILogger<CosmosSourceConfigurationStore> logger)
    {
        _container = container;
        _logger = logger;
    }

    public async Task<IEnumerable<SourceConfiguration>> GetEnabledSourcesAsync(CancellationToken cancellationToken)
    {
        var query = _container.GetItemQueryIterator<SourceConfiguration>(
            "SELECT * FROM c WHERE c.enabled = true ORDER BY c.sourceType, c.id");
        
        var results = new List<SourceConfiguration>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync(cancellationToken);
            results.AddRange(page);
        }
        return results;
    }

    public async Task<IEnumerable<SourceConfiguration>> GetAllSourcesAsync(CancellationToken cancellationToken)
    {
        var query = _container.GetItemQueryIterator<SourceConfiguration>(
            "SELECT * FROM c ORDER BY c.sourceType, c.id");
        
        var results = new List<SourceConfiguration>();
        while (query.HasMoreResults)
        {
            var page = await query.ReadNextAsync(cancellationToken);
            results.AddRange(page);
        }
        return results;
    }

    public async Task<SourceConfiguration?> GetSourceByIdAsync(string id, CancellationToken cancellationToken)
    {
        try
        {
            // For point lookups, we need the partition key. If the ID follows the pattern "sourceType-guid",
            // we extract the sourceType as the partition key.
            var parts = id.Split('-', 2);
            if (parts.Length != 2)
            {
                _logger.LogWarning("Invalid source ID format: {Id}", id);
                return null;
            }
            
            var sourceType = parts[0];
            var response = await _container.ReadItemAsync<SourceConfiguration>(id, new PartitionKey(sourceType), cancellationToken: cancellationToken);
            return response.Resource;
        }
        catch (CosmosException ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<IEnumerable<SourceConfiguration>> GetSourcesByTypeAsync(string sourceType, CancellationToken cancellationToken)
    {
        var queryable = _container.GetItemLinqQueryable<SourceConfiguration>()
            .Where(c => c.SourceType == sourceType)
            .OrderBy(c => c.Id);
        
        var results = new List<SourceConfiguration>();
        var feedIterator = queryable.ToFeedIterator();
        while (feedIterator.HasMoreResults)
        {
            var page = await feedIterator.ReadNextAsync(cancellationToken);
            results.AddRange(page);
        }
        return results;
    }

    public async Task SaveAsync(SourceConfiguration source, CancellationToken cancellationToken)
    {
        try
        {
            await _container.UpsertItemAsync(source, new PartitionKey(source.SourceType), cancellationToken: cancellationToken);
            _logger.LogInformation("Saved source configuration {SourceId} ({SourceType})", source.Id, source.SourceType);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to save source configuration {SourceId}", source.Id);
            throw;
        }
    }

    public async Task DeleteAsync(string id, CancellationToken cancellationToken)
    {
        try
        {
            var parts = id.Split('-', 2);
            if (parts.Length != 2)
                throw new ArgumentException("Invalid source ID format", nameof(id));

            var sourceType = parts[0];
            await _container.DeleteItemAsync<SourceConfiguration>(id, new PartitionKey(sourceType), cancellationToken: cancellationToken);
            _logger.LogInformation("Deleted source configuration {SourceId}", id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to delete source configuration {SourceId}", id);
            throw;
        }
    }

    public async Task ToggleEnabledAsync(string id, bool enabled, CancellationToken cancellationToken)
    {
        var source = await GetSourceByIdAsync(id, cancellationToken);
        if (source is null)
            throw new KeyNotFoundException($"Source {id} not found");

        var updated = source with 
        { 
            Enabled = enabled,
            ModifiedAt = DateTime.UtcNow,
            ModifiedBy = Environment.UserName
        };
        
        await SaveAsync(updated, cancellationToken);
        _logger.LogInformation("Toggled source {SourceId} enabled={Enabled}", id, enabled);
    }

    public async Task UpdateLastRunAsync(
        string id,
        int itemCount,
        bool success,
        string? errorMessage,
        CancellationToken cancellationToken)
    {
        var source = await GetSourceByIdAsync(id, cancellationToken);
        if (source is null)
            throw new KeyNotFoundException($"Source {id} not found");

        var status = success 
            ? $"OK: {itemCount} items at {DateTime.UtcNow:u}"
            : $"FAILED: {errorMessage} at {DateTime.UtcNow:u}";

        var updated = source with
        {
            LastRunAt = success ? DateTime.UtcNow : source.LastRunAt,
            LastRunStatus = status,
            ModifiedAt = DateTime.UtcNow
        };

        await SaveAsync(updated, cancellationToken);
        _logger.LogInformation(
            "Updated source {SourceId} last run: {Status}", id, status);
    }
}

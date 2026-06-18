using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace DataAiMcp.Shared.Ingestion;

/// <summary>
/// Default implementation of ISourceFetcherFactory.
/// Maps source types to registered fetcher implementations.
/// </summary>
public sealed class SourceFetcherFactory : ISourceFetcherFactory
{
    private readonly IServiceProvider _services;
    private readonly ILogger<SourceFetcherFactory> _logger;
    private readonly Dictionary<string, Type> _typeMap;

    public SourceFetcherFactory(
        IServiceProvider services,
        ILogger<SourceFetcherFactory> logger)
    {
        _services = services;
        _logger = logger;
        _typeMap = new(StringComparer.OrdinalIgnoreCase);
    }

    /// <summary>
    /// Registers a fetcher type for a given source type.
    /// Typically called during DI setup.
    /// </summary>
    public void Register(string sourceType, Type fetcherType)
    {
        if (!typeof(ISourceFetcher).IsAssignableFrom(fetcherType))
            throw new ArgumentException($"{fetcherType.Name} does not implement ISourceFetcher");

        _typeMap[sourceType] = fetcherType;
        _logger.LogInformation("Registered fetcher for source type '{SourceType}': {FetcherType}", 
            sourceType, fetcherType.Name);
    }

    public ISourceFetcher CreateFetcher(string sourceType)
    {
        if (!_typeMap.TryGetValue(sourceType, out var fetcherType))
        {
            var supported = string.Join(", ", _typeMap.Keys.OrderBy(x => x));
            throw new NotSupportedException(
                $"Source type '{sourceType}' is not supported. Supported types: {supported}");
        }

        try
        {
            var fetcher = _services.GetRequiredService(fetcherType) as ISourceFetcher;
            return fetcher ?? throw new InvalidOperationException($"Failed to resolve {fetcherType.Name}");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to create fetcher for source type '{SourceType}'", sourceType);
            throw;
        }
    }

    public IReadOnlyList<string> GetSupportedTypes()
    {
        return _typeMap.Keys.OrderBy(x => x).ToList().AsReadOnly();
    }
}

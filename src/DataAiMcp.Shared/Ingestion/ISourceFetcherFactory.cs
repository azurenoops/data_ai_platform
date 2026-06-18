namespace DataAiMcp.Shared.Ingestion;

/// <summary>
/// Factory for creating fetcher instances by source type.
/// Registered as a singleton and used by the dispatcher to instantiate
/// the correct fetcher based on the source type in the configuration.
/// </summary>
public interface ISourceFetcherFactory
{
    /// <summary>
    /// Creates a fetcher for the specified source type.
    /// </summary>
    /// <param name="sourceType">The source type (e.g., "teams", "onedrive", "aws-s3").</param>
    /// <returns>A fetcher instance.</returns>
    /// <exception cref="NotSupportedException">If the source type is not supported.</exception>
    ISourceFetcher CreateFetcher(string sourceType);

    /// <summary>
    /// Gets all supported source types.
    /// </summary>
    IReadOnlyList<string> GetSupportedTypes();
}

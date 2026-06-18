namespace DataAiMcp.Shared.Ingestion;

/// <summary>
/// Contract for a source fetcher. Implementations handle enumeration of items
/// from a specific source type (Teams, OneDrive, AWS S3, etc.) and yield them
/// with their binary content and resolved security IDs.
/// </summary>
public interface ISourceFetcher
{
    /// <summary>
    /// Enumerates items from the source based on the provided settings.
    /// Yields tuples of (blob path, content stream, security IDs).
    /// The blob path should be relative to the landing container (e.g., "teams/12345/file.pdf").
    /// Security IDs are comma-separated AAD object IDs.
    /// </summary>
    /// <param name="settings">Source-specific configuration (team ID, bucket name, etc.).</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    IAsyncEnumerable<(string path, Stream content, string securityIds)> EnumerateAsync(
        IReadOnlyDictionary<string, string> settings,
        CancellationToken cancellationToken);

    /// <summary>
    /// Validates that the source settings are valid and the source is accessible.
    /// Throws InvalidOperationException or returns false if invalid.
    /// </summary>
    Task<bool> ValidateAsync(
        IReadOnlyDictionary<string, string> settings,
        CancellationToken cancellationToken);
}

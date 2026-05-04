namespace DataAiMcp.Shared.Storage;

/// <summary>
/// Repository abstraction over an ADLS Gen2 storage account. Operations are scoped
/// by <see cref="StorageContainer"/> (filesystem) and a logical path inside it.
/// Implementations must be safe for concurrent use from a singleton.
/// </summary>
public interface IDataLakeRepository
{
    Task<Stream> OpenReadAsync(StorageContainer container, string path, CancellationToken cancellationToken);

    Task UploadAsync(
        StorageContainer container,
        string path,
        Stream content,
        string? contentType,
        IReadOnlyDictionary<string, string>? metadata,
        CancellationToken cancellationToken);

    Task<bool> ExistsAsync(StorageContainer container, string path, CancellationToken cancellationToken);

    IAsyncEnumerable<DataLakeItem> ListAsync(
        StorageContainer container,
        string prefix,
        CancellationToken cancellationToken);
}

public enum StorageContainer
{
    Landing,
    Raw,
    Curated,
    Chunks,
}

public sealed record DataLakeItem(string Path, long Length, DateTimeOffset LastModified, string? ETag);

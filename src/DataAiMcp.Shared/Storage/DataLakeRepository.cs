using Azure.Storage.Files.DataLake;
using Azure.Storage.Files.DataLake.Models;
using DataAiMcp.Shared.Auth;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System.Runtime.CompilerServices;

namespace DataAiMcp.Shared.Storage;

public sealed class DataLakeRepository : IDataLakeRepository
{
    private readonly DataLakeServiceClient _service;
    private readonly StorageOptions _options;
    private readonly ILogger<DataLakeRepository> _logger;

    public DataLakeRepository(
        AzureCredentialFactory credentialFactory,
        IOptions<StorageOptions> options,
        ILogger<DataLakeRepository> logger)
    {
        _options = options.Value;
        _logger = logger;
        var endpoint = new Uri($"https://{_options.AccountName}.dfs.core.windows.net");
        _service = new DataLakeServiceClient(endpoint, credentialFactory.Credential);
    }

    public async Task<Stream> OpenReadAsync(StorageContainer container, string path, CancellationToken cancellationToken)
    {
        var fs = GetFileSystem(container);
        var file = fs.GetFileClient(path);
        var response = await file.ReadAsync(cancellationToken).ConfigureAwait(false);
        return response.Value.Content;
    }

    public async Task UploadAsync(
        StorageContainer container,
        string path,
        Stream content,
        string? contentType,
        IReadOnlyDictionary<string, string>? metadata,
        CancellationToken cancellationToken)
    {
        var fs = GetFileSystem(container);
        var file = fs.GetFileClient(path);
        var options = new DataLakeFileUploadOptions
        {
            HttpHeaders = string.IsNullOrEmpty(contentType) ? null : new PathHttpHeaders { ContentType = contentType },
            Metadata = metadata?.ToDictionary(kvp => kvp.Key, kvp => kvp.Value, StringComparer.Ordinal),
        };
        await file.UploadAsync(content, options, cancellationToken).ConfigureAwait(false);
        _logger.LogDebug("Uploaded {Path} to {Container} ({Bytes} bytes).", path, container, content.Length);
    }

    public async Task<bool> ExistsAsync(StorageContainer container, string path, CancellationToken cancellationToken)
    {
        var fs = GetFileSystem(container);
        var file = fs.GetFileClient(path);
        var response = await file.ExistsAsync(cancellationToken).ConfigureAwait(false);
        return response.Value;
    }

    public async IAsyncEnumerable<DataLakeItem> ListAsync(
        StorageContainer container,
        string prefix,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        var fs = GetFileSystem(container);
        await foreach (var path in fs.GetPathsAsync(prefix, recursive: true, cancellationToken: cancellationToken).ConfigureAwait(false))
        {
            if (path.IsDirectory == true) continue;
            // Azure.Storage.Files.DataLake 12.21.0 made PathItem.ETag a non-nullable ETag struct.
            // Preserve previous null-when-missing semantics by mapping default(ETag) to null.
            var etag = path.ETag == default ? null : path.ETag.ToString();
            yield return new DataLakeItem(
                path.Name,
                path.ContentLength ?? 0,
                path.LastModified,
                etag);
        }
    }

    private DataLakeFileSystemClient GetFileSystem(StorageContainer container) =>
        _service.GetFileSystemClient(MapContainer(container));

    private string MapContainer(StorageContainer container) => container switch
    {
        StorageContainer.Landing => _options.LandingContainer,
        StorageContainer.Raw => _options.RawContainer,
        StorageContainer.Curated => _options.CuratedContainer,
        StorageContainer.Chunks => _options.ChunksContainer,
        _ => throw new ArgumentOutOfRangeException(nameof(container), container, "Unknown container."),
    };
}

public sealed class StorageOptions
{
    public const string SectionName = "Storage";

    public string AccountName { get; set; } = "";
    public string LandingContainer { get; set; } = "landing";
    public string RawContainer { get; set; } = "raw";
    public string CuratedContainer { get; set; } = "curated";
    public string ChunksContainer { get; set; } = "chunks";
}

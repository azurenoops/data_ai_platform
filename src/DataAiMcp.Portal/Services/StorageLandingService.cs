using DataAiMcp.Portal.Models;
using Microsoft.Extensions.Options;

namespace DataAiMcp.Portal.Services;

public sealed class StorageLandingService : IStorageLandingService
{
    private readonly PortalOptions _options;
    private readonly IBlobStorageAdapter _blobStorageAdapter;

    public StorageLandingService(IOptions<PortalOptions> options, IBlobStorageAdapter blobStorageAdapter)
    {
        _options = options.Value;
        _blobStorageAdapter = blobStorageAdapter;
    }

    public async Task<string> UploadAsync(string fileName, string? folder, Stream content, CancellationToken cancellationToken)
    {
        var safeName = Path.GetFileName(fileName);
        var normalizedFolder = (folder ?? string.Empty).Trim().Trim('/');
        var objectPath = string.IsNullOrWhiteSpace(normalizedFolder)
            ? safeName
            : $"{normalizedFolder}/{safeName}";

        await _blobStorageAdapter
            .UploadAsync(_options.LandingContainerName, objectPath, content, cancellationToken)
            .ConfigureAwait(false);

        return objectPath;
    }
}

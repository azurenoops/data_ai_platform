using Azure.Identity;
using Azure.Storage.Blobs;
using DataAiMcp.Portal.Models;
using Microsoft.Extensions.Options;

namespace DataAiMcp.Portal.Services;

public sealed class BlobStorageAdapter : IBlobStorageAdapter
{
    private readonly PortalOptions _options;

    public BlobStorageAdapter(IOptions<PortalOptions> options)
    {
        _options = options.Value;
    }

    public async Task UploadAsync(string containerName, string objectPath, Stream content, CancellationToken cancellationToken)
    {
        var blobServiceClient = new BlobServiceClient(
            new Uri(_options.StorageAccountUrl),
            new DefaultAzureCredential());

        var containerClient = blobServiceClient.GetBlobContainerClient(containerName);
        var blobClient = containerClient.GetBlobClient(objectPath);
        await blobClient.UploadAsync(content, overwrite: true, cancellationToken).ConfigureAwait(false);
    }
}

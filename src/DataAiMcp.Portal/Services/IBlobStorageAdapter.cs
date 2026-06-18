namespace DataAiMcp.Portal.Services;

public interface IBlobStorageAdapter
{
    Task UploadAsync(string containerName, string objectPath, Stream content, CancellationToken cancellationToken);
}

namespace DataAiMcp.Portal.Services;

public interface IStorageLandingService
{
    Task<string> UploadAsync(string fileName, string? folder, Stream content, CancellationToken cancellationToken);
}

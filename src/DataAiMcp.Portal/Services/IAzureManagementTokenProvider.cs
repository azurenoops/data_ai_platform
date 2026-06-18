namespace DataAiMcp.Portal.Services;

public interface IAzureManagementTokenProvider
{
    Task<string> GetAccessTokenAsync(CancellationToken cancellationToken);
}

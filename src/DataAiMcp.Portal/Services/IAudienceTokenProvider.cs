namespace DataAiMcp.Portal.Services;

public interface IAudienceTokenProvider
{
    Task<string> GetAccessTokenAsync(string audience, CancellationToken cancellationToken);
}

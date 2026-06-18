using Azure.Core;
using Azure.Identity;

namespace DataAiMcp.Portal.Services;

public sealed class McpAudienceTokenProvider : IAudienceTokenProvider
{
    private readonly TokenCredential _credential;

    public McpAudienceTokenProvider()
    {
        _credential = new DefaultAzureCredential();
    }

    public async Task<string> GetAccessTokenAsync(string audience, CancellationToken cancellationToken)
    {
        var scopeBase = audience.TrimEnd('/');
        var token = await _credential.GetTokenAsync(
            new TokenRequestContext([scopeBase + "/.default"]),
            cancellationToken).ConfigureAwait(false);

        return token.Token;
    }
}

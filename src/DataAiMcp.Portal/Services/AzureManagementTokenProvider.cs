using Azure.Core;
using Azure.Identity;

namespace DataAiMcp.Portal.Services;

public sealed class AzureManagementTokenProvider : IAzureManagementTokenProvider
{
    private static readonly TokenRequestContext Context = new(["https://management.azure.com/.default"]);
    private readonly TokenCredential _credential;

    public AzureManagementTokenProvider()
    {
        _credential = new DefaultAzureCredential();
    }

    public async Task<string> GetAccessTokenAsync(CancellationToken cancellationToken)
    {
        var token = await _credential.GetTokenAsync(Context, cancellationToken).ConfigureAwait(false);
        return token.Token;
    }
}

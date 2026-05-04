using DataAiMcp.Shared.Auth;
using Microsoft.Extensions.Options;
using Microsoft.Graph;

namespace DataAiMcp.Ingestion.Functions.Graph;

/// <summary>
/// Builds a singleton <see cref="GraphServiceClient"/> authenticated with the function app's
/// user-assigned managed identity. Requires the application permissions
/// <c>Sites.Read.All</c>, <c>Files.Read.All</c> (or narrower equivalents) granted to the UAMI.
/// </summary>
public sealed class GraphClientFactory
{
    private static readonly string[] DefaultScopes = ["https://graph.microsoft.com/.default"];

    private readonly Lazy<GraphServiceClient> _client;

    public GraphClientFactory(AzureCredentialFactory credentialFactory, IOptions<GraphOptions> options)
    {
        _ = options;
        _client = new Lazy<GraphServiceClient>(() => new GraphServiceClient(credentialFactory.Credential, DefaultScopes));
    }

    public GraphServiceClient Client => _client.Value;
}

public sealed class GraphOptions
{
    public const string SectionName = "Graph";
    public string TenantId { get; set; } = "";
}

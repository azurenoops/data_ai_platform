using Azure.Core;
using Azure.Identity;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace DataAiMcp.Shared.Auth;

/// <summary>
/// Produces a single shared <see cref="TokenCredential"/> for the process.
/// Uses <see cref="DefaultAzureCredential"/> with optional explicit user-assigned
/// managed identity client ID, which is required when running under multi-UAMI Function Apps / App Services.
/// </summary>
public sealed class AzureCredentialFactory
{
    private readonly Lazy<TokenCredential> _credential;

    public AzureCredentialFactory(IOptions<AzureCredentialOptions> options, ILogger<AzureCredentialFactory> logger)
    {
        var opts = options.Value;
        _credential = new Lazy<TokenCredential>(() =>
        {
            var cred = new DefaultAzureCredential(new DefaultAzureCredentialOptions
            {
                ManagedIdentityClientId = opts.ManagedIdentityClientId,
                TenantId = opts.TenantId,
                ExcludeInteractiveBrowserCredential = true,
                ExcludeVisualStudioCredential = false,
                ExcludeAzureCliCredential = false,
            });
            logger.LogInformation(
                "DefaultAzureCredential created (managedIdentityClientId={ClientIdSet}, tenantId={TenantIdSet}).",
                !string.IsNullOrWhiteSpace(opts.ManagedIdentityClientId),
                !string.IsNullOrWhiteSpace(opts.TenantId));
            return cred;
        });
    }

    public TokenCredential Credential => _credential.Value;
}

public sealed class AzureCredentialOptions
{
    public const string SectionName = "Azure";

    /// <summary>Client ID of the user-assigned managed identity. Set via app setting <c>AZURE_CLIENT_ID</c>.</summary>
    public string? ManagedIdentityClientId { get; set; }

    /// <summary>Entra tenant. Optional - DefaultAzureCredential resolves automatically when omitted.</summary>
    public string? TenantId { get; set; }
}

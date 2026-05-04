using Azure;
using Azure.Search.Documents.Indexes;
using Azure.Search.Documents.Indexes.Models;
using DataAiMcp.Shared.Auth;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace DataAiMcp.Shared.Search;

public sealed class SearchIndexProvisioner
{
    private readonly SearchIndexClient _indexClient;
    private readonly SearchOptions _options;
    private readonly ILogger<SearchIndexProvisioner> _logger;

    public SearchIndexProvisioner(
        AzureCredentialFactory credentialFactory,
        IOptions<SearchOptions> options,
        ILogger<SearchIndexProvisioner> logger)
    {
        _options = options.Value;
        var endpoint = new Uri(_options.Endpoint);
        _indexClient = new SearchIndexClient(endpoint, credentialFactory.Credential);
        _logger = logger;
    }

    public async Task<bool> EnsureIndexAsync(CancellationToken cancellationToken)
    {
        SearchResourceEncryptionKey? cmk = null;
        if (!string.IsNullOrWhiteSpace(_options.CmkKeyVaultUri) && !string.IsNullOrWhiteSpace(_options.CmkKeyName))
        {
            // Per-index CMK. AAD identity is null => Search service uses its system-assigned identity to wrap/unwrap.
            cmk = new SearchResourceEncryptionKey(
                keyName: _options.CmkKeyName,
                keyVersion: _options.CmkKeyVersion ?? string.Empty,
                vaultUri: new Uri(_options.CmkKeyVaultUri).ToString());
            _logger.LogInformation(
                "CMK enabled for Search index using key '{Key}' in vault '{Vault}'.",
                _options.CmkKeyName, _options.CmkKeyVaultUri);
        }

        var index = SearchIndexSchema.Build(cmk);
        try
        {
            var existing = await _indexClient.GetIndexAsync(index.Name, cancellationToken).ConfigureAwait(false);
            if (existing.Value is not null)
            {
                _logger.LogInformation("Search index '{Name}' already exists - applying schema (CreateOrUpdate).", index.Name);
            }
        }
        catch (RequestFailedException ex) when (ex.Status == 404)
        {
            _logger.LogInformation("Search index '{Name}' does not exist - creating.", index.Name);
        }

        var response = await _indexClient.CreateOrUpdateIndexAsync(
            index,
            allowIndexDowntime: false,
            onlyIfUnchanged: false,
            cancellationToken: cancellationToken).ConfigureAwait(false);

        _logger.LogInformation("Search index '{Name}' provisioned ({Fields} fields).", response.Value.Name, response.Value.Fields.Count);
        return true;
    }
}

public sealed class SearchOptions
{
    public const string SectionName = "Search";

    public string Endpoint { get; set; } = "";
    public string IndexName { get; set; } = SearchIndexSchema.IndexName;

    /// <summary>Optional. CMK Key Vault URI (e.g. https://kv-foo.vault.azure.net/). When set with CmkKeyName, indexes are encrypted with CMK.</summary>
    public string? CmkKeyVaultUri { get; set; }

    /// <summary>Optional. CMK key name in the vault.</summary>
    public string? CmkKeyName { get; set; }

    /// <summary>Optional. CMK key version. Empty/null = always use the latest version.</summary>
    public string? CmkKeyVersion { get; set; }

    /// <summary>Optional. Secondary region search endpoint - when set, the dual-write client mirrors writes here for DR.</summary>
    public string? SecondaryEndpoint { get; set; }
}

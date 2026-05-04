using DataAiMcp.Shared.Ai;
using DataAiMcp.Shared.Auth;
using DataAiMcp.Shared.Documents;
using DataAiMcp.Shared.Search;
using DataAiMcp.Shared.Storage;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace DataAiMcp.Shared.DependencyInjection;

/// <summary>
/// Single entry point for both the MCP server and the Function App to wire shared services.
/// Reads bound configuration sections; each service binds to its own section name (see <c>SectionName</c> consts).
/// </summary>
public static class SharedServiceCollectionExtensions
{
    public static IServiceCollection AddDataAiShared(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddOptions<AzureCredentialOptions>()
            .Configure(opts =>
            {
                opts.ManagedIdentityClientId = configuration["AZURE_CLIENT_ID"]
                    ?? configuration["Azure:ManagedIdentityClientId"];
                opts.TenantId = configuration["AZURE_TENANT_ID"]
                    ?? configuration["Azure:TenantId"];
            });
        services.AddSingleton<AzureCredentialFactory>();

        services.AddOptions<StorageOptions>()
            .Bind(configuration.GetSection(StorageOptions.SectionName))
            .ValidateDataAnnotations();
        services.AddSingleton<IDataLakeRepository, DataLakeRepository>();

        services.AddOptions<SearchOptions>()
            .Bind(configuration.GetSection(SearchOptions.SectionName))
            .ValidateDataAnnotations();
        services.AddSingleton<SearchIndexProvisioner>();

        services.AddOptions<FoundryOptions>()
            .Bind(configuration.GetSection(FoundryOptions.SectionName))
            .ValidateDataAnnotations();
        services.AddSingleton<FoundryClientFactory>();

        services.AddOptions<DocumentIntelligenceOptions>()
            .Bind(configuration.GetSection(DocumentIntelligenceOptions.SectionName));
        services.AddSingleton<DocumentLayoutExtractor>();

        services.AddSingleton<MarkdownChunker>(_ => new MarkdownChunker(new ChunkerOptions
        {
            TargetTokens = int.TryParse(configuration["Chunker:TargetTokens"], out var t) ? t : 800,
            OverlapTokens = int.TryParse(configuration["Chunker:OverlapTokens"], out var o) ? o : 100,
        }));

        return services;
    }
}

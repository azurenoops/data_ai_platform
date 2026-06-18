using Azure.Search.Documents;
using Microsoft.Azure.Cosmos;
using DataAiMcp.Ingestion.Functions.Pipeline;
using DataAiMcp.Shared.Auth;
using DataAiMcp.Shared.DependencyInjection;
using DataAiMcp.Shared.Ingestion;
using DataAiMcp.Shared.Search;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using DataAiSearchOptions = DataAiMcp.Shared.Search.SearchOptions;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

builder.Services.AddApplicationInsightsTelemetryWorkerService();
builder.Services.ConfigureFunctionsApplicationInsights();

builder.Services.AddDataAiShared(builder.Configuration);

builder.Services.AddHttpClient();

builder.Services.AddSingleton<SearchClient>(sp =>
{
    var cred = sp.GetRequiredService<AzureCredentialFactory>().Credential;
    var opts = sp.GetRequiredService<IOptions<DataAiSearchOptions>>().Value;
    return new SearchClient(new Uri(opts.Endpoint), opts.IndexName, cred);
});

// Index writer: dual-write fan-out when Search:SecondaryEndpoint is configured (DR), single otherwise.
builder.Services.AddSingleton<IIndexWriter>(sp =>
    DualWriteSearchIndexWriter.Create(
        sp.GetRequiredService<AzureCredentialFactory>(),
        sp.GetRequiredService<IOptions<DataAiSearchOptions>>(),
        sp.GetRequiredService<ILoggerFactory>()));

builder.Services.AddSingleton<DocumentIngestionPipeline>();

// Source configuration store (CosmosDB-backed)
builder.Services.AddSingleton<ISourceConfigurationStore, CosmosSourceConfigurationStore>(sp =>
{
    var cosmosEndpoint = builder.Configuration["CosmosDb:Endpoint"]
        ?? throw new InvalidOperationException("CosmosDb:Endpoint not configured");
    var cosmosDatabaseId = builder.Configuration["CosmosDb:DatabaseId"]
        ?? "ingestion";
    var cosmosContainerId = builder.Configuration["CosmosDb:SourceConfigContainerId"]
        ?? "source-configurations";
    
    var credential = sp.GetRequiredService<AzureCredentialFactory>().Credential;
    var client = new CosmosClient(cosmosEndpoint, credential);
    var database = client.GetDatabase(cosmosDatabaseId);
    var container = database.GetContainer(cosmosContainerId);
    var logger = sp.GetRequiredService<ILoggerFactory>().CreateLogger<CosmosSourceConfigurationStore>();
    return new CosmosSourceConfigurationStore(container, logger);
});

// Source fetcher factory (extensible via registration)
builder.Services.AddSingleton<ISourceFetcherFactory>(sp =>
{
    var factory = new SourceFetcherFactory(sp, sp.GetRequiredService<ILoggerFactory>().CreateLogger<SourceFetcherFactory>());
    // Register existing fetchers (to be implemented incrementally)
    // factory.Register("onedrive", typeof(OneDriveSourceFetcher));
    // factory.Register("sharepoint", typeof(SharePointSourceFetcher));
    // factory.Register("teams", typeof(TeamsSourceFetcher));
    return factory;
});

builder.Logging.AddFilter("Azure", LogLevel.Warning);

builder.Build().Run();

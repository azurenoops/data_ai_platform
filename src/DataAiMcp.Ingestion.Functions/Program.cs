using Azure.Search.Documents;
using DataAiMcp.Ingestion.Functions.Graph;
using DataAiMcp.Ingestion.Functions.Pipeline;
using DataAiMcp.Shared.Auth;
using DataAiMcp.Shared.DependencyInjection;
using DataAiMcp.Shared.Search;
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

builder.Services.AddOptions<GraphOptions>()
    .Bind(builder.Configuration.GetSection(GraphOptions.SectionName));
builder.Services.AddSingleton<GraphClientFactory>();
builder.Services.AddSingleton<GraphFileFetcher>();

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

builder.Logging.AddFilter("Azure", LogLevel.Warning);

builder.Build().Run();

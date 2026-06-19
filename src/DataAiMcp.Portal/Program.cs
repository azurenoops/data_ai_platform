using Microsoft.Azure.Cosmos;
using DataAiMcp.Portal.Models;
using DataAiMcp.Portal.Services;
using DataAiMcp.Shared.DependencyInjection;
using DataAiMcp.Shared.Ingestion;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.Extensions.Options;
using Microsoft.Identity.Web;
using Microsoft.Identity.Web.UI;

var builder = WebApplication.CreateBuilder(args);

var azureAdSection = builder.Configuration.GetSection("AzureAd");
var azureAdClientId = azureAdSection["ClientId"];
if (string.IsNullOrWhiteSpace(azureAdClientId) || azureAdClientId == "00000000-0000-0000-0000-000000000000")
{
    throw new InvalidOperationException("AzureAd:ClientId must be configured with a valid app registration client id.");
}

// Add services to the container.
builder.Services
    .AddOptions<PortalOptions>()
    .Bind(builder.Configuration.GetSection("Portal"))
    .ValidateDataAnnotations()
    .ValidateOnStart();

builder.Services.AddDataAiShared(builder.Configuration);

builder.Services.AddHttpClient<IMcpProbeService, McpProbeService>();
builder.Services.AddHttpClient<IDataFactoryService, DataFactoryService>();
builder.Services.AddSingleton<IAudienceTokenProvider, McpAudienceTokenProvider>();
builder.Services.AddSingleton<IMcpToolService, McpToolService>();
builder.Services.AddSingleton<IChatAnswerService, ChatAnswerService>();
builder.Services.AddSingleton<IEnvironmentDiagnosticsService, EnvironmentDiagnosticsService>();
builder.Services.AddSingleton<IAzureManagementTokenProvider, AzureManagementTokenProvider>();
builder.Services.AddSingleton<IBlobStorageAdapter, BlobStorageAdapter>();
builder.Services.AddSingleton<IStorageLandingService, StorageLandingService>();
builder.Services.AddSingleton<ISourceFetcherFactory, SourceFetcherFactory>();

// Source configuration services (for dynamic source management)
builder.Services.AddSingleton<ISourceConfigurationService, SourceConfigurationService>();
builder.Services.AddSingleton<ISourceConfigurationStore, CosmosSourceConfigurationStore>(sp =>
{
    var cosmosEndpoint = builder.Configuration["CosmosDb:Endpoint"]
        ?? throw new InvalidOperationException("CosmosDb:Endpoint not configured");
    var cosmosDatabaseId = builder.Configuration["CosmosDb:DatabaseId"]
        ?? "ingestion";
    var cosmosContainerId = builder.Configuration["CosmosDb:SourceConfigContainerId"]
        ?? "source-configurations";
    
    var credential = sp.GetRequiredService<Azure.Core.TokenCredential>();
    var client = new Microsoft.Azure.Cosmos.CosmosClient(cosmosEndpoint, credential);
    var container = client.GetDatabase(cosmosDatabaseId).GetContainer(cosmosContainerId);
    var logger = sp.GetRequiredService<ILoggerFactory>().CreateLogger<CosmosSourceConfigurationStore>();
    return new CosmosSourceConfigurationStore(container, logger);
});

builder.Services
    .AddAuthentication(OpenIdConnectDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApp(azureAdSection);

builder.Services.PostConfigure<OpenIdConnectOptions>(OpenIdConnectDefaults.AuthenticationScheme, options =>
{
    options.ClientId = azureAdClientId;
});

builder.Services.AddAuthorization();

builder.Services.AddAntiforgery(options => options.HeaderName = "RequestVerificationToken");

builder.Services
    .AddRazorPages(options =>
    {
        options.Conventions.AuthorizeFolder("/");
        options.Conventions.AllowAnonymousToPage("/Error");
    })
    .AddMicrosoftIdentityUI();

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var oidcOptions = scope.ServiceProvider
        .GetRequiredService<IOptionsMonitor<OpenIdConnectOptions>>()
        .Get(OpenIdConnectDefaults.AuthenticationScheme);
    app.Logger.LogInformation("Effective OIDC client id: {ClientId}", oidcOptions.ClientId);
}

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}

app.UseHttpsRedirection();

app.UseRouting();

app.UseAuthentication();
app.UseAuthorization();

app.MapStaticAssets();
app.MapControllers();
app.MapRazorPages()
   .WithStaticAssets();

app.Run();

public partial class Program;

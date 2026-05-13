using Azure.Monitor.OpenTelemetry.AspNetCore;
using Azure.Search.Documents;
using DataAiMcp.McpServer.Auth;
using DataAiMcp.McpServer.Rag;
using DataAiMcp.McpServer.Resources;
using DataAiMcp.McpServer.Synapse;
using DataAiMcp.McpServer.Tools;
using DataAiMcp.Shared.Auth;
using DataAiMcp.Shared.DependencyInjection;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;
using DataAiSearchOptions = DataAiMcp.Shared.Search.SearchOptions;

var builder = WebApplication.CreateBuilder(args);

// ---- Shared services ----
builder.Services.AddDataAiShared(builder.Configuration);

// ---- Tool dependencies ----
builder.Services.Configure<DatasetCatalogOptions>(builder.Configuration);
builder.Services.Configure<SourceCatalogOptions>(builder.Configuration);
builder.Services.Configure<SynapseOptions>(builder.Configuration.GetSection(SynapseOptions.SectionName));
builder.Services.Configure<McpAuthOptions>(builder.Configuration.GetSection(McpAuthOptions.SectionName));

builder.Services.AddSingleton<SearchClient>(sp =>
{
    var cred = sp.GetRequiredService<AzureCredentialFactory>().Credential;
    var opts = sp.GetRequiredService<IOptions<DataAiSearchOptions>>().Value;
    return new SearchClient(new Uri(opts.Endpoint), opts.IndexName, cred);
});

builder.Services.AddSingleton<RagOrchestrator>();
builder.Services.AddSingleton<SynapseQueryClient>();
builder.Services.AddSingleton<SqlGenerator>();
builder.Services.AddSingleton<CuratedDocumentResources>();

// ---- Caller security context (per-request ACL trimming) ----
builder.Services.AddHttpContextAccessor();
builder.Services.AddSingleton<CallerSecurityContext>();

// ---- Auth ----
var authOptions = builder.Configuration.GetSection(McpAuthOptions.SectionName).Get<McpAuthOptions>() ?? new McpAuthOptions();
if (authOptions.RequireAuthenticatedUser)
{
    builder.Services
        .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
        .AddJwtBearer(options =>
        {
            options.Authority = $"https://login.microsoftonline.com/{authOptions.TenantId}/v2.0";
            options.Audience = authOptions.Audience;
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidateAudience = true,
                ValidateLifetime = true,
                ValidateIssuerSigningKey = true,
                ClockSkew = TimeSpan.FromMinutes(2),
            };
        });

    builder.Services.AddAuthorization(o =>
    {
        o.AddPolicy(McpPolicies.ReadDocuments, p => p.RequireAuthenticatedUser());
        o.AddPolicy(McpPolicies.QueryStructured, p => p.RequireAuthenticatedUser());
        o.AddPolicy(McpPolicies.AdminTools, p => p.RequireAuthenticatedUser().RequireClaim("roles", "DataAiMcp.Admin"));
    });
}
else
{
    builder.Services.AddAuthorization(o =>
    {
        o.AddPolicy(McpPolicies.ReadDocuments, p => p.RequireAssertion(_ => true));
        o.AddPolicy(McpPolicies.QueryStructured, p => p.RequireAssertion(_ => true));
        o.AddPolicy(McpPolicies.AdminTools, p => p.RequireAssertion(_ => true));
    });
}

// ---- MCP server ----
builder.Services.AddMcpServer()
    .WithHttpTransport()
    .WithTools<SearchTools>()
    .WithTools<StructuredTools>()
    .WithTools<MetadataTools>();

// ---- OpenTelemetry ----
builder.Services.AddOpenTelemetry()
    .WithTracing(t => t
        .AddSource(DataAiMcp.Shared.Telemetry.DataAiTelemetry.SourceName)
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation())
    .WithMetrics(m => m
        .AddMeter(DataAiMcp.Shared.Telemetry.DataAiTelemetry.MeterName)
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation());

if (!string.IsNullOrEmpty(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]))
{
    builder.Services.AddOpenTelemetry().UseAzureMonitor();
}

builder.Services.AddProblemDetails();

var app = builder.Build();

if (authOptions.RequireAuthenticatedUser)
{
    app.UseAuthentication();
}
app.UseAuthorization();

app.MapGet("/healthz", () => Results.Ok(new { status = "ok" })).AllowAnonymous();
app.MapGet("/", () => Results.Ok(new { service = "DataAiMcp.McpServer", mcp = "/mcp" })).AllowAnonymous();

var mcpEndpoint = app.MapMcp("/mcp");
if (authOptions.RequireAuthenticatedUser)
{
    mcpEndpoint.RequireAuthorization(McpPolicies.ReadDocuments);
}

app.Run();

public partial class Program;

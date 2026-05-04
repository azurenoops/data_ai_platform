using FluentAssertions;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Xunit;

namespace DataAiMcp.McpServer.Tests;

public sealed class HealthEndpointTests : IClassFixture<McpServerFactory>
{
    private readonly McpServerFactory _factory;

    public HealthEndpointTests(McpServerFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Healthz_returnsOk()
    {
        using var client = _factory.CreateClient();
        var response = await client.GetAsync("/healthz");
        response.IsSuccessStatusCode.Should().BeTrue();
    }

    [Fact]
    public async Task Root_returnsServiceMetadata()
    {
        using var client = _factory.CreateClient();
        var response = await client.GetAsync("/");
        response.IsSuccessStatusCode.Should().BeTrue();
        var body = await response.Content.ReadAsStringAsync();
        body.Should().Contain("DataAiMcp.McpServer");
        body.Should().Contain("/mcp");
    }
}

public sealed class McpServerFactory : WebApplicationFactory<Program>
{
    protected override IHost CreateHost(IHostBuilder builder)
    {
        builder.ConfigureHostConfiguration(config =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Auth:RequireAuthenticatedUser"] = "false",
                ["Search:Endpoint"] = "https://example.search.windows.net",
                ["Search:IndexName"] = "documents",
                ["Storage:AccountName"] = "examplestorage",
                ["Foundry:Endpoint"] = "https://example.cognitiveservices.azure.com/",
                ["Foundry:ChatDeployment"] = "gpt-4o",
                ["Foundry:EmbeddingDeployment"] = "text-embedding-3-large",
                ["Synapse:ServerlessSqlEndpoint"] = "example-ondemand.sql.azuresynapse.net",
            });
        });
        return base.CreateHost(builder);
    }
}

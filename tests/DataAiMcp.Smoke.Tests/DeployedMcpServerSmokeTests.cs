using FluentAssertions;
using Xunit;

namespace DataAiMcp.Smoke.Tests;

/// <summary>
/// Smoke checks invoked by <c>infra/scripts/postdeploy.sh</c>. Reads <c>MCP_SERVER_BASE_URL</c>
/// from environment (set by azd) and probes the deployed App Service.
/// </summary>
public sealed class DeployedMcpServerSmokeTests
{
    [Fact]
    public async Task Healthz_isReachable()
    {
        var baseUrl = Environment.GetEnvironmentVariable("MCP_SERVER_BASE_URL");
        if (string.IsNullOrEmpty(baseUrl))
        {
            // Smoke tests run only after `azd up`; no-op locally.
            return;
        }

        using var client = new HttpClient();
        var response = await client.GetAsync($"{baseUrl!.TrimEnd('/')}/healthz");
        response.IsSuccessStatusCode.Should().BeTrue();
    }
}

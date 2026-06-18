using DataAiMcp.Portal.Models;
using Microsoft.Extensions.Options;

namespace DataAiMcp.Portal.Services;

public sealed class McpProbeService : IMcpProbeService
{
    private readonly HttpClient _httpClient;
    private readonly PortalOptions _options;

    public McpProbeService(HttpClient httpClient, IOptions<PortalOptions> options)
    {
        _httpClient = httpClient;
        _options = options.Value;
    }

    public async Task<(bool IsHealthy, string Detail)> CheckHealthAsync(CancellationToken cancellationToken)
    {
        var url = $"{_options.McpBaseUrl.TrimEnd('/')}/healthz";

        try
        {
            using var response = await _httpClient.GetAsync(url, cancellationToken).ConfigureAwait(false);
            var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            if (response.IsSuccessStatusCode)
            {
                return (true, body);
            }

            return (false, $"HTTP {(int)response.StatusCode}: {body}");
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
    }
}

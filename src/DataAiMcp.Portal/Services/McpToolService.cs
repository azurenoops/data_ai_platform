using System.Text;
using System.Text.Json;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json.Nodes;
using DataAiMcp.Portal.Models;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;

namespace DataAiMcp.Portal.Services;

public sealed class McpToolService : IMcpToolService
{
    private static readonly JsonSerializerOptions PrettyJsonOptions = new() { WriteIndented = true };

    private readonly PortalOptions _options;
    private readonly IAudienceTokenProvider _tokenProvider;
    private readonly ILogger<McpToolService> _logger;

    public McpToolService(IOptions<PortalOptions> options, IAudienceTokenProvider tokenProvider, ILogger<McpToolService> logger)
    {
        _options = options.Value;
        _tokenProvider = tokenProvider;
        _logger = logger;
    }

    public async Task<SourceCatalogResult> GetSourceCatalogAsync(CancellationToken cancellationToken)
    {
        var (client, tokenSummary) = await CreateClientAsync(cancellationToken).ConfigureAwait(false);
        await using var _ = client;

        CallToolResult sourcesResult;
        try
        {
            sourcesResult = await client.CallToolAsync(
                "list_sources",
                new Dictionary<string, object?>(),
                null,
                null,
                cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                $"MCP list_sources failed ({tokenSummary}): {FirstLine(ex.Message)}",
                ex);
        }

        CallToolResult datasetsResult;
        try
        {
            datasetsResult = await client.CallToolAsync(
                "describe_dataset",
                new Dictionary<string, object?>(),
                null,
                null,
                cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                $"MCP describe_dataset failed ({tokenSummary}): {FirstLine(ex.Message)}",
                ex);
        }

        var sourcesJson = ExtractToolPayload(sourcesResult);
        var datasetsJson = ExtractToolPayload(datasetsResult);

        return new SourceCatalogResult
        {
            Sources = ParseSources(sourcesJson),
            Datasets = ParseDatasets(datasetsJson),
        };
    }

    public async Task<string> ExecuteToolAsync(string toolName, IReadOnlyDictionary<string, object?> arguments, CancellationToken cancellationToken)
    {
        var (client, _) = await CreateClientAsync(cancellationToken).ConfigureAwait(false);
        await using var _ = client;
        var result = await client.CallToolAsync(toolName, arguments, null, null, cancellationToken).ConfigureAwait(false);

        var payload = ExtractToolPayload(result);
        return TryFormatJson(payload);
    }

    private async Task<(IMcpClient Client, string TokenSummary)> CreateClientAsync(CancellationToken cancellationToken)
    {
        var token = await _tokenProvider.GetAccessTokenAsync(_options.McpAudience, cancellationToken).ConfigureAwait(false);
        var endpoint = new Uri($"{_options.McpBaseUrl.TrimEnd('/')}/mcp");
        var tokenSummary = BuildTokenSummary(token);

        using (var probeClient = new HttpClient())
        {
            using var probeRequest = new HttpRequestMessage(HttpMethod.Get, endpoint);
            probeRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            using var probeResponse = await probeClient.SendAsync(probeRequest, cancellationToken).ConfigureAwait(false);
            if (probeResponse.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            {
                var responseBody = await probeResponse.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
                throw new InvalidOperationException(
                    $"MCP auth probe rejected token with HTTP {(int)probeResponse.StatusCode} ({probeResponse.StatusCode}) ({tokenSummary}). Body: {FirstLine(responseBody)}");
            }
        }

        var transport = new SseClientTransport(new SseClientTransportOptions
        {
            Endpoint = endpoint,
            Name = "portal-mcp",
            AdditionalHeaders = new Dictionary<string, string>
            {
                ["Authorization"] = $"Bearer {token}",
            },
        });

        try
        {
            var client = await McpClientFactory.CreateAsync(transport, null, null, cancellationToken).ConfigureAwait(false);
            _logger.LogInformation("Portal MCP client connected ({TokenSummary})", tokenSummary);
            return (client, tokenSummary);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                $"MCP client connection failed ({tokenSummary}): {FirstLine(ex.Message)}",
                ex);
        }
    }

    private static string FirstLine(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return string.Empty;
        }

        return text.Split('\n', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()?.Trim() ?? string.Empty;
    }

    private static string BuildTokenSummary(string token)
    {
        try
        {
            var parts = token.Split('.');
            if (parts.Length < 2)
            {
                return "token=non-jwt";
            }

            var payload = parts[1];
            payload = payload.PadRight(payload.Length + ((4 - (payload.Length % 4)) % 4), '=');
            var json = Encoding.UTF8.GetString(Convert.FromBase64String(payload.Replace('-', '+').Replace('_', '/')));
            var node = JsonNode.Parse(json)?.AsObject();
            if (node is null)
            {
                return "token=jwt(unreadable-payload)";
            }

            static string GetClaim(JsonObject o, string name)
            {
                return o.TryGetPropertyValue(name, out var value) ? value?.ToString() ?? string.Empty : string.Empty;
            }

            var aud = GetClaim(node, "aud");
            var iss = GetClaim(node, "iss");
            var tid = GetClaim(node, "tid");
            var appid = GetClaim(node, "appid");
            var azp = GetClaim(node, "azp");
            var oid = GetClaim(node, "oid");
            return $"aud={aud}; iss={iss}; tid={tid}; appid={appid}; azp={azp}; oid={oid}";
        }
        catch
        {
            return "token=jwt(parse-failed)";
        }
    }

    private static string ExtractToolPayload(CallToolResult result)
    {
        if (result.Content.Count == 0)
        {
            return "{}";
        }

        var builder = new StringBuilder();
        foreach (var item in result.Content)
        {
            if (item is TextContentBlock text)
            {
                if (builder.Length > 0)
                {
                    builder.AppendLine();
                }

                builder.Append(text.Text);
            }
        }

        if (builder.Length == 0)
        {
            return JsonSerializer.Serialize(result.Content);
        }

        return builder.ToString();
    }

    private static IReadOnlyList<SourceCatalogItem> ParseSources(string payload)
    {
        try
        {
            using var document = JsonDocument.Parse(payload);
            if (document.RootElement.ValueKind != JsonValueKind.Array)
            {
                return Array.Empty<SourceCatalogItem>();
            }

            var list = new List<SourceCatalogItem>();
            foreach (var item in document.RootElement.EnumerateArray())
            {
                list.Add(new SourceCatalogItem
                {
                    Name = GetString(item, "name"),
                    Description = GetString(item, "description"),
                    DocumentCount = GetInt32(item, "documentCount"),
                });
            }

            return list;
        }
        catch
        {
            return Array.Empty<SourceCatalogItem>();
        }
    }

    private static IReadOnlyList<DatasetCatalogItem> ParseDatasets(string payload)
    {
        try
        {
            using var document = JsonDocument.Parse(payload);
            if (document.RootElement.ValueKind != JsonValueKind.Array)
            {
                return Array.Empty<DatasetCatalogItem>();
            }

            var list = new List<DatasetCatalogItem>();
            foreach (var item in document.RootElement.EnumerateArray())
            {
                var columns = new List<DatasetColumnItem>();
                if (item.TryGetProperty("columns", out var columnsElement) && columnsElement.ValueKind == JsonValueKind.Array)
                {
                    foreach (var column in columnsElement.EnumerateArray())
                    {
                        columns.Add(new DatasetColumnItem
                        {
                            Name = GetString(column, "name"),
                            DataType = GetString(column, "dataType"),
                            Description = GetString(column, "description"),
                        });
                    }
                }

                var sampleQuestions = new List<string>();
                if (item.TryGetProperty("sampleQuestions", out var sampleQuestionsElement) && sampleQuestionsElement.ValueKind == JsonValueKind.Array)
                {
                    foreach (var question in sampleQuestionsElement.EnumerateArray())
                    {
                        if (question.ValueKind == JsonValueKind.String)
                        {
                            sampleQuestions.Add(question.GetString() ?? string.Empty);
                        }
                    }
                }

                list.Add(new DatasetCatalogItem
                {
                    Name = GetString(item, "name"),
                    Description = GetString(item, "description"),
                    ViewName = GetString(item, "viewName"),
                    Columns = columns,
                    SampleQuestions = sampleQuestions,
                });
            }

            return list;
        }
        catch
        {
            return Array.Empty<DatasetCatalogItem>();
        }
    }

    private static string GetString(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString() ?? string.Empty
            : string.Empty;
    }

    private static int GetInt32(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.Number && property.TryGetInt32(out var value)
            ? value
            : 0;
    }

    private static string TryFormatJson(string payload)
    {
        try
        {
            using var document = JsonDocument.Parse(payload);
            return JsonSerializer.Serialize(document.RootElement, PrettyJsonOptions);
        }
        catch
        {
            return payload;
        }
    }
}

using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using DataAiMcp.Portal.Models;
using Microsoft.Extensions.Options;

namespace DataAiMcp.Portal.Services;

public sealed class DataFactoryService : IDataFactoryService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private readonly HttpClient _httpClient;
    private readonly PortalOptions _options;
    private readonly IAzureManagementTokenProvider _tokenProvider;

    public DataFactoryService(
        HttpClient httpClient,
        IOptions<PortalOptions> options,
        IAzureManagementTokenProvider tokenProvider)
    {
        _httpClient = httpClient;
        _options = options.Value;
        _tokenProvider = tokenProvider;
    }

    public async Task<string> StartPipelineRunAsync(CancellationToken cancellationToken)
    {
        var url = BuildPipelineCreateRunUrl();
        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent("{}", Encoding.UTF8, "application/json"),
        };
        await AuthorizeAsync(request, cancellationToken).ConfigureAwait(false);

        using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var responseText = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();

        using var json = JsonDocument.Parse(responseText);
        return json.RootElement.GetProperty("runId").GetString() ?? string.Empty;
    }

    public async Task<PipelineRunInfo> GetPipelineRunAsync(string runId, CancellationToken cancellationToken)
    {
        var url = BuildPipelineRunGetUrl(runId);
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        await AuthorizeAsync(request, cancellationToken).ConfigureAwait(false);

        using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var responseText = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();

        using var json = JsonDocument.Parse(responseText);
        var root = json.RootElement;

        return new PipelineRunInfo
        {
            RunId = root.GetProperty("runId").GetString() ?? runId,
            Status = root.GetProperty("status").GetString() ?? "Unknown",
            RunStart = TryGetDateTimeOffset(root, "runStart"),
            RunEnd = TryGetDateTimeOffset(root, "runEnd"),
            Message = root.TryGetProperty("message", out var message) ? message.GetString() ?? string.Empty : string.Empty,
        };
    }

    public async Task<IReadOnlyList<CopyActivitySummary>> GetCopyActivitySummariesAsync(string runId, CancellationToken cancellationToken)
    {
        var url = BuildActivityRunQueryUrl();
        var queryPayload = new
        {
            lastUpdatedAfter = DateTime.UtcNow.AddHours(-2).ToString("O"),
            lastUpdatedBefore = DateTime.UtcNow.ToString("O"),
            filters = new[]
            {
                new
                {
                    operand = "PipelineRunId",
                    @operator = "Equals",
                    values = new[] { runId },
                },
            },
        };

        var body = JsonSerializer.Serialize(queryPayload, JsonOptions);
        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json"),
        };

        await AuthorizeAsync(request, cancellationToken).ConfigureAwait(false);

        using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var responseText = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();

        using var json = JsonDocument.Parse(responseText);
        if (!json.RootElement.TryGetProperty("value", out var values) || values.ValueKind != JsonValueKind.Array)
        {
            return Array.Empty<CopyActivitySummary>();
        }

        var summaries = new List<CopyActivitySummary>();
        foreach (var item in values.EnumerateArray())
        {
            var output = item.TryGetProperty("output", out var outputElement) ? outputElement : default;
            var error = item.TryGetProperty("error", out var errorElement) ? errorElement : default;

            summaries.Add(new CopyActivitySummary
            {
                ActivityName = item.TryGetProperty("activityName", out var activityName) ? activityName.GetString() ?? string.Empty : string.Empty,
                Status = item.TryGetProperty("status", out var status) ? status.GetString() ?? string.Empty : string.Empty,
                RowsCopied = TryGetInt64(output, "rowsCopied"),
                FilesWritten = TryGetInt64(output, "filesWritten"),
                DataRead = TryGetInt64(output, "dataRead"),
                ErrorCode = TryGetString(error, "errorCode"),
            });
        }

        return summaries
            .Where(s => string.Equals(s.ActivityName, "CopyTable", StringComparison.OrdinalIgnoreCase))
            .OrderByDescending(s => s.RowsCopied)
            .ToList();
    }

    private async Task AuthorizeAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var token = await _tokenProvider.GetAccessTokenAsync(cancellationToken).ConfigureAwait(false);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
    }

    private string BuildPipelineCreateRunUrl()
    {
        return string.Concat(
            "https://management.azure.com/subscriptions/", _options.SubscriptionId,
            "/resourceGroups/", _options.ResourceGroupName,
            "/providers/Microsoft.DataFactory/factories/", _options.DataFactoryName,
            "/pipelines/", _options.SqlPipelineName,
            "/createRun?api-version=2018-06-01");
    }

    private string BuildPipelineRunGetUrl(string runId)
    {
        return string.Concat(
            "https://management.azure.com/subscriptions/", _options.SubscriptionId,
            "/resourceGroups/", _options.ResourceGroupName,
            "/providers/Microsoft.DataFactory/factories/", _options.DataFactoryName,
            "/pipelineruns/", runId,
            "?api-version=2018-06-01");
    }

    private string BuildActivityRunQueryUrl()
    {
        return string.Concat(
            "https://management.azure.com/subscriptions/", _options.SubscriptionId,
            "/resourceGroups/", _options.ResourceGroupName,
            "/providers/Microsoft.DataFactory/factories/", _options.DataFactoryName,
            "/queryActivityruns?api-version=2018-06-01");
    }

    private static DateTimeOffset? TryGetDateTimeOffset(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var property) || property.ValueKind != JsonValueKind.String)
        {
            return null;
        }

        return DateTimeOffset.TryParse(property.GetString(), out var value) ? value : null;
    }

    private static long TryGetInt64(JsonElement element, string propertyName)
    {
        if (element.ValueKind == JsonValueKind.Undefined || !element.TryGetProperty(propertyName, out var property))
        {
            return 0;
        }

        if (property.ValueKind == JsonValueKind.Number && property.TryGetInt64(out var number))
        {
            return number;
        }

        return 0;
    }

    private static string TryGetString(JsonElement element, string propertyName)
    {
        if (element.ValueKind == JsonValueKind.Undefined || !element.TryGetProperty(propertyName, out var property))
        {
            return string.Empty;
        }

        return property.GetString() ?? string.Empty;
    }
}

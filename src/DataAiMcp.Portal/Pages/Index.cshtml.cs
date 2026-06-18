using DataAiMcp.Portal.Models;
using DataAiMcp.Portal.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.Extensions.Options;

namespace DataAiMcp.Portal.Pages;

public class IndexModel : PageModel
{
    private readonly PortalOptions _options;
    private readonly IMcpProbeService _mcpProbeService;
    private readonly IEnvironmentDiagnosticsService _environmentDiagnosticsService;

    public IndexModel(
        IOptions<PortalOptions> options,
        IMcpProbeService mcpProbeService,
        IEnvironmentDiagnosticsService environmentDiagnosticsService)
    {
        _options = options.Value;
        _mcpProbeService = mcpProbeService;
        _environmentDiagnosticsService = environmentDiagnosticsService;
    }

    public bool IsMcpHealthy { get; private set; }

    public string HealthDetail { get; private set; } = string.Empty;

    public string McpBaseUrl => _options.McpBaseUrl;

    public string McpAudience => _options.McpAudience;

    public string SubscriptionId => _options.SubscriptionId;

    public string ResourceGroupName => _options.ResourceGroupName;

    public string DataFactoryName => _options.DataFactoryName;

    public string SqlPipelineName => _options.SqlPipelineName;

    public string StorageAccountUrl => _options.StorageAccountUrl;

    public string LandingContainerName => _options.LandingContainerName;

    public string DashboardMcpStatus { get; private set; } = "Not run";

    public string DashboardCatalogStatus { get; private set; } = "Not run";

    public string DashboardDataFactoryStatus { get; private set; } = "Not run";

    public async Task OnGetAsync(CancellationToken cancellationToken)
    {
        var (isHealthy, detail) = await _mcpProbeService.CheckHealthAsync(cancellationToken).ConfigureAwait(false);
        IsMcpHealthy = isHealthy;
        HealthDetail = detail;

        var snapshot = await _environmentDiagnosticsService.RunAsync(cancellationToken).ConfigureAwait(false);
        DashboardMcpStatus = snapshot.McpHealthStatus;
        DashboardCatalogStatus = snapshot.SourceCatalogStatus;
        DashboardDataFactoryStatus = snapshot.DataFactoryStatus;
    }

    public async Task<IActionResult> OnGetStatusAsync(CancellationToken cancellationToken)
    {
        var snapshot = await _environmentDiagnosticsService.RunAsync(cancellationToken).ConfigureAwait(false);
        return new JsonResult(new
        {
            mcpStatus = snapshot.McpHealthStatus,
            catalogStatus = snapshot.SourceCatalogStatus,
            dataFactoryStatus = snapshot.DataFactoryStatus,
            refreshedAtUtc = DateTimeOffset.UtcNow,
        });
    }
}

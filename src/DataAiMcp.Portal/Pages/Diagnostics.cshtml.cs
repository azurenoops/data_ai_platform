using DataAiMcp.Portal.Models;
using DataAiMcp.Portal.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.Extensions.Options;

namespace DataAiMcp.Portal.Pages;

public class DiagnosticsModel : PageModel
{
    private readonly PortalOptions _options;
    private readonly IEnvironmentDiagnosticsService _environmentDiagnosticsService;

    public DiagnosticsModel(
        IOptions<PortalOptions> options,
        IEnvironmentDiagnosticsService environmentDiagnosticsService)
    {
        _options = options.Value;
        _environmentDiagnosticsService = environmentDiagnosticsService;
    }

    public string McpBaseUrl => _options.McpBaseUrl;

    public string McpAudience => _options.McpAudience;

    public string SubscriptionId => _options.SubscriptionId;

    public string ResourceGroupName => _options.ResourceGroupName;

    public string DataFactoryName => _options.DataFactoryName;

    public string SqlPipelineName => _options.SqlPipelineName;

    public string StorageAccountUrl => _options.StorageAccountUrl;

    public string LandingContainerName => _options.LandingContainerName;

    public string McpHealthStatus { get; private set; } = "Not run";

    public string SourceCatalogStatus { get; private set; } = "Not run";

    public string DataFactoryStatus { get; private set; } = "Not run";

    public string Details { get; private set; } = string.Empty;

    public void OnGet()
    {
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        var snapshot = await _environmentDiagnosticsService.RunAsync(cancellationToken).ConfigureAwait(false);
        McpHealthStatus = snapshot.McpHealthStatus;
        SourceCatalogStatus = snapshot.SourceCatalogStatus;
        DataFactoryStatus = snapshot.DataFactoryStatus;
        Details = snapshot.Details;
        return Page();
    }
}

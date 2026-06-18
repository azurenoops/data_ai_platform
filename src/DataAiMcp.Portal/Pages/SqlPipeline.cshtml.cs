using DataAiMcp.Portal.Models;
using DataAiMcp.Portal.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.Extensions.Options;

namespace DataAiMcp.Portal.Pages;

public class SqlPipelineModel : PageModel
{
    private readonly IDataFactoryService _dataFactoryService;
    private readonly IMcpProbeService _mcpProbeService;
    private readonly PortalOptions _options;

    public SqlPipelineModel(
        IDataFactoryService dataFactoryService,
        IMcpProbeService mcpProbeService,
        IOptions<PortalOptions> options)
    {
        _dataFactoryService = dataFactoryService;
        _mcpProbeService = mcpProbeService;
        _options = options.Value;
    }

    [BindProperty]
    public string RunId { get; set; } = string.Empty;

    public PipelineRunInfo? RunInfo { get; private set; }

    public IReadOnlyList<CopyActivitySummary> Activities { get; private set; } = Array.Empty<CopyActivitySummary>();

    public string ResultMessage { get; private set; } = string.Empty;

    public bool IsSuccess { get; private set; }

    public bool IsMcpHealthy { get; private set; }

    public string HealthDetail { get; private set; } = string.Empty;

    public string McpBaseUrl => _options.McpBaseUrl;

    public string McpAudience => _options.McpAudience;

    public long TotalRowsCopied => Activities.Sum(a => a.RowsCopied);

    public long TotalFilesWritten => Activities.Sum(a => a.FilesWritten);

    public long TotalDataRead => Activities.Sum(a => a.DataRead);

    public async Task OnGetAsync(CancellationToken cancellationToken)
    {
        await LoadHealthAsync(cancellationToken).ConfigureAwait(false);
    }

    public async Task<IActionResult> OnPostStartAsync(CancellationToken cancellationToken)
    {
        try
        {
            RunId = await _dataFactoryService.StartPipelineRunAsync(cancellationToken).ConfigureAwait(false);
            await LoadRunDetailsAsync(cancellationToken).ConfigureAwait(false);
            await LoadHealthAsync(cancellationToken).ConfigureAwait(false);
            IsSuccess = true;
            ResultMessage = $"Pipeline started: {RunId}";
        }
        catch (Exception ex)
        {
            IsSuccess = false;
            ResultMessage = $"Failed to start pipeline: {ex.Message}";
        }

        return Page();
    }

    public async Task<IActionResult> OnPostRefreshAsync(CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(RunId))
        {
            IsSuccess = false;
            ResultMessage = "Enter or start a run before refreshing.";
            return Page();
        }

        try
        {
            await LoadRunDetailsAsync(cancellationToken).ConfigureAwait(false);
            await LoadHealthAsync(cancellationToken).ConfigureAwait(false);
            IsSuccess = true;
            ResultMessage = $"Run {RunId} refreshed.";
        }
        catch (Exception ex)
        {
            IsSuccess = false;
            ResultMessage = $"Failed to refresh run: {ex.Message}";
        }

        return Page();
    }

    private async Task LoadRunDetailsAsync(CancellationToken cancellationToken)
    {
        RunInfo = await _dataFactoryService.GetPipelineRunAsync(RunId, cancellationToken).ConfigureAwait(false);
        Activities = await _dataFactoryService.GetCopyActivitySummariesAsync(RunId, cancellationToken).ConfigureAwait(false);
    }

    private async Task LoadHealthAsync(CancellationToken cancellationToken)
    {
        var (isHealthy, detail) = await _mcpProbeService.CheckHealthAsync(cancellationToken).ConfigureAwait(false);
        IsMcpHealthy = isHealthy;
        HealthDetail = detail;
    }
}

using DataAiMcp.Ingestion.Functions.Graph;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace DataAiMcp.Ingestion.Functions;

/// <summary>
/// Timer-trigger that walks each configured SharePoint drive and lands new files into
/// <c>landing/sharepoint/</c>, which then triggers <see cref="IngestBlobFunction"/>.
/// </summary>
public sealed class SharePointFilesFunction
{
    private readonly GraphFileFetcher _fetcher;
    private readonly IConfiguration _config;
    private readonly ILogger<SharePointFilesFunction> _logger;

    public SharePointFilesFunction(GraphFileFetcher fetcher, IConfiguration config, ILogger<SharePointFilesFunction> logger)
    {
        _fetcher = fetcher;
        _config = config;
        _logger = logger;
    }

    /// <summary>Every 30 minutes by default; override via app setting <c>SharePoint:Schedule</c>.</summary>
    [Function("SharePointFilesSync")]
    public async Task RunAsync([TimerTrigger("%SharePoint:Schedule%")] TimerInfo timer, CancellationToken cancellationToken)
    {
        var driveIds = (_config["SharePoint:DriveIds"] ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (driveIds.Length == 0)
        {
            _logger.LogInformation("SharePoint:DriveIds empty - nothing to do.");
            return;
        }

        var total = 0;
        foreach (var driveId in driveIds)
        {
            total += await _fetcher.SyncDriveAsync(driveId, source: "sharepoint", landingPathPrefix: "sharepoint", cancellationToken).ConfigureAwait(false);
        }
        _logger.LogInformation("SharePoint sync landed {Count} new files.", total);
    }
}

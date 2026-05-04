using DataAiMcp.Ingestion.Functions.Graph;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace DataAiMcp.Ingestion.Functions;

/// <summary>Timer-trigger pull from one or more OneDrive personal/business drives via Graph.</summary>
public sealed class OneDriveFilesFunction
{
    private readonly GraphFileFetcher _fetcher;
    private readonly IConfiguration _config;
    private readonly ILogger<OneDriveFilesFunction> _logger;

    public OneDriveFilesFunction(GraphFileFetcher fetcher, IConfiguration config, ILogger<OneDriveFilesFunction> logger)
    {
        _fetcher = fetcher;
        _config = config;
        _logger = logger;
    }

    [Function("OneDriveFilesSync")]
    public async Task RunAsync([TimerTrigger("%OneDrive:Schedule%")] TimerInfo timer, CancellationToken cancellationToken)
    {
        var driveIds = (_config["OneDrive:DriveIds"] ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (driveIds.Length == 0)
        {
            _logger.LogInformation("OneDrive:DriveIds empty - nothing to do.");
            return;
        }

        var total = 0;
        foreach (var driveId in driveIds)
        {
            total += await _fetcher.SyncDriveAsync(driveId, source: "onedrive", landingPathPrefix: "onedrive", cancellationToken).ConfigureAwait(false);
        }
        _logger.LogInformation("OneDrive sync landed {Count} new files.", total);
    }
}

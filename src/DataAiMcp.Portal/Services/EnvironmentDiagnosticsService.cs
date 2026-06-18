using System.Text;
using DataAiMcp.Portal.Models;

namespace DataAiMcp.Portal.Services;

public sealed class EnvironmentDiagnosticsService : IEnvironmentDiagnosticsService
{
    private readonly IMcpProbeService _mcpProbeService;
    private readonly IMcpToolService _mcpToolService;
    private readonly IDataFactoryService _dataFactoryService;

    public EnvironmentDiagnosticsService(
        IMcpProbeService mcpProbeService,
        IMcpToolService mcpToolService,
        IDataFactoryService dataFactoryService)
    {
        _mcpProbeService = mcpProbeService;
        _mcpToolService = mcpToolService;
        _dataFactoryService = dataFactoryService;
    }

    public async Task<DiagnosticsSnapshot> RunAsync(CancellationToken cancellationToken)
    {
        var snapshot = new DiagnosticsSnapshot();
        var details = new StringBuilder();

        var (healthy, healthDetail) = await _mcpProbeService.CheckHealthAsync(cancellationToken).ConfigureAwait(false);
        snapshot.McpHealthStatus = healthy ? "OK" : "Failed";
        details.Append("MCP health detail: ");
        details.AppendLine(healthDetail);

        try
        {
            var catalog = await _mcpToolService.GetSourceCatalogAsync(cancellationToken).ConfigureAwait(false);
            snapshot.SourceCatalogStatus = $"OK ({catalog.Sources.Count} sources, {catalog.Datasets.Count} datasets)";
        }
        catch (Exception ex)
        {
            var reason = ex.Message.Split('\n', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()?.Trim();
            snapshot.SourceCatalogStatus = string.IsNullOrWhiteSpace(reason)
                ? "Failed"
                : $"Failed ({reason})";
            details.Append("Source catalog error: ");
            details.AppendLine(ex.Message);
        }

        try
        {
            _ = await _dataFactoryService.GetPipelineRunAsync("diagnostic-nonexistent-run", cancellationToken).ConfigureAwait(false);
            snapshot.DataFactoryStatus = "OK";
        }
        catch (Exception ex)
        {
            snapshot.DataFactoryStatus = ex.Message.Contains("404", StringComparison.OrdinalIgnoreCase)
                ? "Reachable (nonexistent run id)"
                : "Failed";

            details.Append("Data factory detail: ");
            details.AppendLine(ex.Message);
        }

        snapshot.Details = details.ToString().Trim();
        return snapshot;
    }
}

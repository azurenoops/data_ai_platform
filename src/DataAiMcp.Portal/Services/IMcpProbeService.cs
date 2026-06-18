namespace DataAiMcp.Portal.Services;

public interface IMcpProbeService
{
    Task<(bool IsHealthy, string Detail)> CheckHealthAsync(CancellationToken cancellationToken);
}

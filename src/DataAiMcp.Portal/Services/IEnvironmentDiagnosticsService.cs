using DataAiMcp.Portal.Models;

namespace DataAiMcp.Portal.Services;

public interface IEnvironmentDiagnosticsService
{
    Task<DiagnosticsSnapshot> RunAsync(CancellationToken cancellationToken);
}

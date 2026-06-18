using DataAiMcp.Portal.Models;

namespace DataAiMcp.Portal.Services;

public interface IMcpToolService
{
    Task<SourceCatalogResult> GetSourceCatalogAsync(CancellationToken cancellationToken);

    Task<string> ExecuteToolAsync(string toolName, IReadOnlyDictionary<string, object?> arguments, CancellationToken cancellationToken);
}

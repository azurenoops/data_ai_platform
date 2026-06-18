using DataAiMcp.Portal.Models;

namespace DataAiMcp.Portal.Services;

public interface IDataFactoryService
{
    Task<string> StartPipelineRunAsync(CancellationToken cancellationToken);

    Task<PipelineRunInfo> GetPipelineRunAsync(string runId, CancellationToken cancellationToken);

    Task<IReadOnlyList<CopyActivitySummary>> GetCopyActivitySummariesAsync(string runId, CancellationToken cancellationToken);
}

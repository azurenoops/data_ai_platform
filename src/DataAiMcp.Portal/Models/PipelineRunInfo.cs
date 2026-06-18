namespace DataAiMcp.Portal.Models;

public sealed class PipelineRunInfo
{
    public string RunId { get; set; } = string.Empty;

    public string Status { get; set; } = string.Empty;

    public DateTimeOffset? RunStart { get; set; }

    public DateTimeOffset? RunEnd { get; set; }

    public string Message { get; set; } = string.Empty;
}

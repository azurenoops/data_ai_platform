namespace DataAiMcp.Portal.Models;

public sealed class DiagnosticsSnapshot
{
    public string McpHealthStatus { get; set; } = "Not run";

    public string SourceCatalogStatus { get; set; } = "Not run";

    public string DataFactoryStatus { get; set; } = "Not run";

    public string Details { get; set; } = string.Empty;
}

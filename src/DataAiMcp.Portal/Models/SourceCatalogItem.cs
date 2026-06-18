namespace DataAiMcp.Portal.Models;

public sealed class SourceCatalogItem
{
    public string Name { get; set; } = string.Empty;

    public string Description { get; set; } = string.Empty;

    public int DocumentCount { get; set; }
}

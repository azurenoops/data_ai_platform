namespace DataAiMcp.Portal.Models;

public sealed class SourceCatalogResult
{
    public IReadOnlyList<SourceCatalogItem> Sources { get; set; } = Array.Empty<SourceCatalogItem>();

    public IReadOnlyList<DatasetCatalogItem> Datasets { get; set; } = Array.Empty<DatasetCatalogItem>();
}

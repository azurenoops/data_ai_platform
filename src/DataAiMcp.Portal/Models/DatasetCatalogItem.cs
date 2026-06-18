namespace DataAiMcp.Portal.Models;

public sealed class DatasetCatalogItem
{
    public string Name { get; set; } = string.Empty;

    public string Description { get; set; } = string.Empty;

    public string ViewName { get; set; } = string.Empty;

    public IReadOnlyList<DatasetColumnItem> Columns { get; set; } = Array.Empty<DatasetColumnItem>();

    public IReadOnlyList<string> SampleQuestions { get; set; } = Array.Empty<string>();
}

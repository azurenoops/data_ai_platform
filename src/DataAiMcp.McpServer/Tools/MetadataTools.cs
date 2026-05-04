using System.ComponentModel;
using DataAiMcp.Shared.Models;
using Microsoft.Extensions.Options;
using ModelContextProtocol.Server;

namespace DataAiMcp.McpServer.Tools;

[McpServerToolType]
public sealed class MetadataTools
{
    private readonly SourceCatalogOptions _sources;

    public MetadataTools(IOptions<SourceCatalogOptions> sources)
    {
        _sources = sources.Value;
    }

    [McpServerTool(Name = "list_sources")]
    [Description("List the configured ingestion sources (e.g. SharePoint, OneDrive, SQL MI, Dataverse) with descriptions.")]
    public IReadOnlyList<SourceInfo> ListSources()
    {
        return _sources.Sources
            .Select(s => new SourceInfo(s.Name, s.Description, s.DocumentCount))
            .ToArray();
    }
}

public sealed class SourceCatalogOptions
{
    public List<SourceCatalogEntry> Sources { get; set; } = new();
}

public sealed class SourceCatalogEntry
{
    public string Name { get; set; } = "";
    public string Description { get; set; } = "";
    public int DocumentCount { get; set; }
}

using System.ComponentModel;
using DataAiMcp.McpServer.Auth;
using DataAiMcp.McpServer.Rag;
using DataAiMcp.Shared.Models;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ModelContextProtocol.Server;

namespace DataAiMcp.McpServer.Tools;

[McpServerToolType]
public sealed class MetadataTools
{
    private readonly SourceCatalogOptions _sources;
    private readonly RagOrchestrator _rag;
    private readonly CallerSecurityContext _caller;
    private readonly ILogger<MetadataTools> _logger;

    public MetadataTools(
        IOptions<SourceCatalogOptions> sources,
        RagOrchestrator rag,
        CallerSecurityContext caller,
        ILogger<MetadataTools> logger)
    {
        _sources = sources.Value;
        _rag = rag;
        _caller = caller;
        _logger = logger;
    }

    [McpServerTool(Name = "list_sources")]
    [Description("List the configured ingestion sources (e.g. SharePoint, OneDrive, SQL MI, Dataverse) with descriptions and live document counts.")]
    public async Task<IReadOnlyList<SourceInfo>> ListSourcesAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            // Query the search index to get actual document counts per source,
            // respecting the caller's security context (so they only see docs they can access).
            var counts = await _rag.CountDocumentsBySourceAsync(_caller.SecurityIds, cancellationToken).ConfigureAwait(false);

            var result = _sources.Sources
                .Select(s => new SourceInfo(
                    s.Name,
                    s.Description,
                    counts.TryGetValue(s.Name, out var count) ? count : 0))
                .ToArray();

            _logger.LogInformation("list_sources returned {SourceCount} sources with document counts.", result.Length);
            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to count documents by source; falling back to empty counts.");
            // Fallback: return sources with 0 documents if the search query fails.
            return _sources.Sources
                .Select(s => new SourceInfo(s.Name, s.Description, 0))
                .ToArray();
        }
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
}

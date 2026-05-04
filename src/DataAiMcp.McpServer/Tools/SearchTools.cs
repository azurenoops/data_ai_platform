using System.ComponentModel;
using DataAiMcp.McpServer.Auth;
using DataAiMcp.McpServer.Rag;
using DataAiMcp.Shared.Models;
using ModelContextProtocol.Server;

namespace DataAiMcp.McpServer.Tools;

[McpServerToolType]
public sealed class SearchTools
{
    private readonly RagOrchestrator _rag;
    private readonly CallerSecurityContext _caller;

    public SearchTools(RagOrchestrator rag, CallerSecurityContext caller)
    {
        _rag = rag;
        _caller = caller;
    }

    [McpServerTool(Name = "search_documents")]
    [Description("Hybrid (BM25 + vector + semantic-rerank) search across the unified document corpus. Returns top chunks with citations.")]
    public async Task<IReadOnlyList<SearchHit>> SearchDocumentsAsync(
        [Description("Free-text query.")] string query,
        [Description("Maximum chunks to return (default 8).")] int top = 8,
        [Description("Optional source filter, e.g. 'sharepoint' / 'onedrive' / 'sqlmi'.")] string? source = null,
        CancellationToken cancellationToken = default)
    {
        var aclIds = _caller.SecurityIds;
        return await _rag.SearchAsync(query, top, source, aclIds, cancellationToken).ConfigureAwait(false);
    }

    [McpServerTool(Name = "get_document")]
    [Description("Returns the full contiguous chunk list for a given documentId, ordered by chunk index.")]
    public async Task<IReadOnlyList<SearchHit>> GetDocumentAsync(
        [Description("Document identifier returned from search_documents.")] string documentId,
        CancellationToken cancellationToken = default)
    {
        var aclIds = _caller.SecurityIds;
        return await _rag.GetDocumentAsync(documentId, aclIds, cancellationToken).ConfigureAwait(false);
    }
}

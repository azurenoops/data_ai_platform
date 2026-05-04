using Azure.Search.Documents;
using Azure.Search.Documents.Models;
using DataAiMcp.Shared.Ai;
using DataAiMcp.Shared.Models;
using DataAiMcp.Shared.Search;
using DataAiMcp.Shared.Telemetry;
using Microsoft.Extensions.Logging;
using AzureSearchOptions = Azure.Search.Documents.SearchOptions;

namespace DataAiMcp.McpServer.Rag;

/// <summary>
/// Hybrid retrieval over the documents index. Steps:
/// 1) Embed the query via Foundry embeddings deployment.
/// 2) Issue a semantic-rerank-enabled hybrid search (BM25 + vector) against AI Search.
/// 3) Project results into <see cref="SearchHit"/> with snippets + reranker scores.
/// </summary>
public sealed class RagOrchestrator
{
    private readonly SearchClient _search;
    private readonly FoundryClientFactory _foundry;
    private readonly ILogger<RagOrchestrator> _logger;

    public RagOrchestrator(SearchClient search, FoundryClientFactory foundry, ILogger<RagOrchestrator> logger)
    {
        _search = search;
        _foundry = foundry;
        _logger = logger;
    }

    public async Task<IReadOnlyList<SearchHit>> SearchAsync(
        string query,
        int top,
        string? source,
        IReadOnlyCollection<string>? callerSecurityIds,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(query)) return Array.Empty<SearchHit>();

        var embedder = _foundry.CreateEmbeddingGenerator();
        var embedStart = DateTimeOffset.UtcNow;
        var embedding = await embedder.GenerateAsync([query], cancellationToken: cancellationToken).ConfigureAwait(false);
        DataAiTelemetry.EmbeddingLatencyMs.Record((DateTimeOffset.UtcNow - embedStart).TotalMilliseconds);

        var options = new AzureSearchOptions
        {
            Size = top,
            QueryType = SearchQueryType.Semantic,
            SemanticSearch = new SemanticSearchOptions
            {
                SemanticConfigurationName = SearchIndexSchema.SemanticConfigName,
                QueryCaption = new QueryCaption(QueryCaptionType.Extractive),
                QueryAnswer = new QueryAnswer(QueryAnswerType.Extractive),
            },
            VectorSearch = new VectorSearchOptions
            {
                Queries =
                {
                    new VectorizedQuery(embedding[0].Vector)
                    {
                        KNearestNeighborsCount = Math.Max(top, 50),
                        Fields = { SearchIndexSchema.ContentVectorField },
                    },
                },
            },
        };
        options.Select.Add(SearchIndexSchema.IdField);
        options.Select.Add(SearchIndexSchema.DocumentIdField);
        options.Select.Add(SearchIndexSchema.TitleField);
        options.Select.Add(SearchIndexSchema.ContentField);
        options.Select.Add(SearchIndexSchema.SourceField);
        options.Select.Add(SearchIndexSchema.SourcePathField);
        options.Select.Add(SearchIndexSchema.PageField);

        options.Filter = BuildFilter(source, callerSecurityIds);

        var searchStart = DateTimeOffset.UtcNow;
        var response = await _search.SearchAsync<SearchDocument>(query, options, cancellationToken).ConfigureAwait(false);
        DataAiTelemetry.SearchLatencyMs.Record((DateTimeOffset.UtcNow - searchStart).TotalMilliseconds);

        var hits = new List<SearchHit>();
        await foreach (var page in response.Value.GetResultsAsync().AsPages())
        {
            foreach (var item in page.Values)
            {
                hits.Add(Project(item));
            }
        }

        _logger.LogInformation(
            "search_documents query='{Query}' source={Source} aclFilter={AclFiltered} returned {Count} hits.",
            query, source, callerSecurityIds is { Count: > 0 }, hits.Count);
        return hits;
    }

    public async Task<IReadOnlyList<SearchHit>> GetDocumentAsync(
        string documentId,
        IReadOnlyCollection<string>? callerSecurityIds,
        CancellationToken cancellationToken)
    {
        var idFilter = $"{SearchIndexSchema.DocumentIdField} eq '{documentId.Replace("'", "''", StringComparison.Ordinal)}'";
        var aclFilter = BuildAclFilter(callerSecurityIds);
        var combined = string.IsNullOrEmpty(aclFilter) ? idFilter : $"{idFilter} and {aclFilter}";

        var options = new AzureSearchOptions
        {
            Filter = combined,
            Size = 200,
            OrderBy = { $"{SearchIndexSchema.ChunkIndexField} asc" },
        };
        options.Select.Add(SearchIndexSchema.IdField);
        options.Select.Add(SearchIndexSchema.DocumentIdField);
        options.Select.Add(SearchIndexSchema.TitleField);
        options.Select.Add(SearchIndexSchema.ContentField);
        options.Select.Add(SearchIndexSchema.SourceField);
        options.Select.Add(SearchIndexSchema.SourcePathField);
        options.Select.Add(SearchIndexSchema.PageField);

        var response = await _search.SearchAsync<SearchDocument>("*", options, cancellationToken).ConfigureAwait(false);

        var hits = new List<SearchHit>();
        await foreach (var page in response.Value.GetResultsAsync().AsPages())
        {
            foreach (var item in page.Values)
            {
                hits.Add(Project(item));
            }
        }
        return hits;
    }

    private static string? BuildFilter(string? source, IReadOnlyCollection<string>? callerSecurityIds)
    {
        var clauses = new List<string>(2);
        if (!string.IsNullOrEmpty(source))
        {
            clauses.Add($"{SearchIndexSchema.SourceField} eq '{source.Replace("'", "''", StringComparison.Ordinal)}'");
        }
        var acl = BuildAclFilter(callerSecurityIds);
        if (!string.IsNullOrEmpty(acl))
        {
            clauses.Add(acl);
        }
        return clauses.Count == 0 ? null : string.Join(" and ", clauses);
    }

    /// <summary>
    /// Builds the OData ACL clause: <c>securityIds/any(s: search.in(s, '&lt;ids&gt;', ','))</c>.
    /// Returns null when no caller IDs are supplied (dev mode / no auth) - the caller is then unfiltered.
    /// </summary>
    private static string? BuildAclFilter(IReadOnlyCollection<string>? callerSecurityIds)
    {
        if (callerSecurityIds is null || callerSecurityIds.Count == 0) return null;

        // OData literal escaping: single quote -> two single quotes. We also reject any caller ID that
        // contains a comma to avoid breaking the search.in delimiter.
        var safe = callerSecurityIds
            .Where(id => !string.IsNullOrEmpty(id) && !id.Contains(',', StringComparison.Ordinal))
            .Select(id => id.Replace("'", "''", StringComparison.Ordinal))
            .ToArray();
        if (safe.Length == 0) return null;
        var csv = string.Join(",", safe);
        return $"{SearchIndexSchema.SecurityIdsField}/any(s: search.in(s, '{csv}', ','))";
    }

    private static SearchHit Project(SearchResult<SearchDocument> item)
    {
        var doc = item.Document;
        return new SearchHit
        {
            Id = doc.GetString(SearchIndexSchema.IdField) ?? "",
            DocumentId = doc.GetString(SearchIndexSchema.DocumentIdField) ?? "",
            Title = doc.GetString(SearchIndexSchema.TitleField) ?? "",
            Snippet = Truncate(doc.GetString(SearchIndexSchema.ContentField), 1200),
            Source = doc.GetString(SearchIndexSchema.SourceField) ?? "",
            SourcePath = doc.GetString(SearchIndexSchema.SourcePathField) ?? "",
            Page = doc.GetInt32(SearchIndexSchema.PageField) ?? 0,
            Score = item.Score ?? 0,
            RerankerScore = item.SemanticSearch?.RerankerScore,
        };
    }

    private static string Truncate(string? value, int maxLength)
    {
        if (string.IsNullOrEmpty(value)) return "";
        return value.Length <= maxLength ? value : value[..maxLength] + "…";
    }
}

using System.Text.Json.Serialization;

namespace DataAiMcp.Shared.Models;

/// <summary>
/// Persisted record indexed into the AI Search documents index.
/// Field names align with <see cref="Search.SearchIndexSchema"/>.
/// JsonPropertyName attributes pin the camelCase JSON wire shape that AI Search expects.
/// </summary>
public sealed class IndexDocument
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("documentId")] public string DocumentId { get; set; } = "";
    [JsonPropertyName("title")] public string Title { get; set; } = "";
    [JsonPropertyName("content")] public string Content { get; set; } = "";
    [JsonPropertyName("contentVector")] public IReadOnlyList<float> ContentVector { get; set; } = Array.Empty<float>();
    [JsonPropertyName("source")] public string Source { get; set; } = "";
    [JsonPropertyName("sourcePath")] public string SourcePath { get; set; } = "";
    [JsonPropertyName("page")] public int Page { get; set; }
    [JsonPropertyName("chunkIndex")] public int ChunkIndex { get; set; }
    [JsonPropertyName("lastModified")] public DateTimeOffset LastModified { get; set; }
    [JsonPropertyName("metadata")] public string Metadata { get; set; } = "{}";
    [JsonPropertyName("securityIds")] public IReadOnlyList<string> SecurityIds { get; set; } = Array.Empty<string>();
}

/// <summary>Result returned by <c>search_documents</c> MCP tool.</summary>
public sealed class SearchHit
{
    public string Id { get; set; } = "";
    public string DocumentId { get; set; } = "";
    public string Title { get; set; } = "";
    public string Snippet { get; set; } = "";
    public string Source { get; set; } = "";
    public string SourcePath { get; set; } = "";
    public int Page { get; set; }
    public double Score { get; set; }
    public double? RerankerScore { get; set; }
}

/// <summary>Result returned by <c>list_sources</c>.</summary>
public sealed record SourceInfo(string Name, string Description, int DocumentCount);

/// <summary>Result returned by <c>describe_dataset</c>.</summary>
public sealed class DatasetDescriptor
{
    public string Name { get; set; } = "";
    public string Description { get; set; } = "";
    public string ViewName { get; set; } = "";
    public IReadOnlyList<DatasetColumn> Columns { get; set; } = Array.Empty<DatasetColumn>();
    public IReadOnlyList<string> SampleQuestions { get; set; } = Array.Empty<string>();
}

public sealed record DatasetColumn(string Name, string DataType, string? Description);

/// <summary>Result returned by <c>query_structured_data</c>.</summary>
public sealed class StructuredQueryResult
{
    public string GeneratedSql { get; set; } = "";
    public IReadOnlyList<IReadOnlyDictionary<string, object?>> Rows { get; set; } = Array.Empty<IReadOnlyDictionary<string, object?>>();
    public int RowCount { get; set; }
    public string? Truncated { get; set; }
}

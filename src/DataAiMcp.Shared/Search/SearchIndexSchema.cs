using Azure.Search.Documents.Indexes.Models;

namespace DataAiMcp.Shared.Search;

/// <summary>
/// Schema for the central <c>documents</c> index. Vector profile + semantic config are deliberately co-located
/// so the provisioner stays declarative and the MCP server can re-use the same field names for hybrid queries.
/// </summary>
public static class SearchIndexSchema
{
    public const string IndexName = "documents";
    public const string VectorProfileName = "default-vector-profile";
    public const string VectorAlgorithmName = "default-hnsw";
    public const string SemanticConfigName = "default-semantic";

    public const int EmbeddingDimensions = 3072; // text-embedding-3-large

    public const string IdField = "id";
    public const string DocumentIdField = "documentId";
    public const string TitleField = "title";
    public const string ContentField = "content";
    public const string ContentVectorField = "contentVector";
    public const string SourceField = "source";
    public const string SourcePathField = "sourcePath";
    public const string PageField = "page";
    public const string ChunkIndexField = "chunkIndex";
    public const string LastModifiedField = "lastModified";
    public const string MetadataField = "metadata";
    public const string SecurityIdsField = "securityIds";

    public static SearchIndex Build(SearchResourceEncryptionKey? encryptionKey = null)
    {
        var fields = new List<SearchField>
        {
            new SimpleField(IdField, SearchFieldDataType.String) { IsKey = true, IsFilterable = true },
            new SimpleField(DocumentIdField, SearchFieldDataType.String) { IsFilterable = true, IsFacetable = true },
            new SearchableField(TitleField) { IsFilterable = true, IsSortable = true },
            new SearchableField(ContentField) { AnalyzerName = LexicalAnalyzerName.StandardLucene },
            new VectorSearchField(ContentVectorField, EmbeddingDimensions, VectorProfileName),
            new SimpleField(SourceField, SearchFieldDataType.String) { IsFilterable = true, IsFacetable = true },
            new SimpleField(SourcePathField, SearchFieldDataType.String) { IsFilterable = true },
            new SimpleField(PageField, SearchFieldDataType.Int32) { IsFilterable = true, IsSortable = true },
            new SimpleField(ChunkIndexField, SearchFieldDataType.Int32) { IsFilterable = true, IsSortable = true },
            new SimpleField(LastModifiedField, SearchFieldDataType.DateTimeOffset) { IsFilterable = true, IsSortable = true },
            new SimpleField(MetadataField, SearchFieldDataType.String) { IsFilterable = false },
            new SimpleField(SecurityIdsField, SearchFieldDataType.Collection(SearchFieldDataType.String)) { IsFilterable = true },
        };

        var vectorSearch = new VectorSearch
        {
            Profiles =
            {
                new VectorSearchProfile(VectorProfileName, VectorAlgorithmName),
            },
            Algorithms =
            {
                new HnswAlgorithmConfiguration(VectorAlgorithmName)
                {
                    Parameters = new HnswParameters
                    {
                        Metric = VectorSearchAlgorithmMetric.Cosine,
                        M = 4,
                        EfConstruction = 400,
                        EfSearch = 500,
                    },
                },
            },
        };

        var semanticSearch = new SemanticSearch
        {
            Configurations =
            {
                new SemanticConfiguration(
                    SemanticConfigName,
                    new SemanticPrioritizedFields
                    {
                        TitleField = new SemanticField(TitleField),
                        ContentFields = { new SemanticField(ContentField) },
                        KeywordsFields = { new SemanticField(SourceField) },
                    }),
            },
        };

        var index = new SearchIndex(IndexName, fields)
        {
            VectorSearch = vectorSearch,
            SemanticSearch = semanticSearch,
        };
        if (encryptionKey is not null)
        {
            index.EncryptionKey = encryptionKey;
        }
        return index;
    }
}

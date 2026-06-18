using System.ClientModel;
using System.Text.Json;
using Azure;
using Azure.Search.Documents;
using Azure.Search.Documents.Models;
using DataAiMcp.Shared.Ai;
using DataAiMcp.Shared.Documents;
using DataAiMcp.Shared.Models;
using DataAiMcp.Shared.Search;
using DataAiMcp.Shared.Storage;
using DataAiMcp.Shared.Telemetry;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;

namespace DataAiMcp.Ingestion.Functions.Pipeline;

/// <summary>
/// Document ingestion pipeline: <c>landing/*</c> blob → Document Intelligence (markdown layout)
/// → MarkdownChunker → embeddings → AI Search upsert.
/// </summary>
public sealed class DocumentIngestionPipeline
{
    private readonly DocumentLayoutExtractor _layout;
    private readonly MarkdownChunker _chunker;
    private readonly FoundryClientFactory _foundry;
    private readonly IIndexWriter _search;
    private readonly IDataLakeRepository _lake;
    private readonly ILogger<DocumentIngestionPipeline> _logger;

    public DocumentIngestionPipeline(
        DocumentLayoutExtractor layout,
        MarkdownChunker chunker,
        FoundryClientFactory foundry,
        IIndexWriter search,
        IDataLakeRepository lake,
        ILogger<DocumentIngestionPipeline> logger)
    {
        _layout = layout;
        _chunker = chunker;
        _foundry = foundry;
        _search = search;
        _lake = lake;
        _logger = logger;
    }

    public async Task<int> IngestAsync(
        string blobName,
        Stream content,
        IReadOnlyDictionary<string, string>? blobMetadata,
        CancellationToken cancellationToken)
    {
        using var activity = DataAiTelemetry.ActivitySource.StartActivity("ingest.document");
        activity?.SetTag("blob.name", blobName);

        // 1) DocIntel layout → markdown
        var layout = await _layout.ExtractAsync(content, cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(layout.Markdown))
        {
            _logger.LogWarning("DocIntel returned empty content for {Blob}; skipping.", blobName);
            return 0;
        }

        // 2) Chunk
        var chunks = _chunker.Chunk(layout.Markdown);
        if (chunks.Count == 0)
        {
            _logger.LogWarning("Chunker emitted 0 chunks for {Blob}; skipping.", blobName);
            return 0;
        }

        // 3) Persist raw markdown for traceability
        var markdownPath = $"{Path.ChangeExtension(blobName, ".md")}";
        await using (var ms = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(layout.Markdown)))
        {
            await _lake.UploadAsync(
                StorageContainer.Chunks,
                markdownPath,
                ms,
                contentType: "text/markdown",
                metadata: null,
                cancellationToken: cancellationToken).ConfigureAwait(false);
        }

        // 4) Embeddings (batched with throttling/backoff so large files do not exceed the
        //    embedding deployment's per-minute token rate limit in a single request)
        var embedder = _foundry.CreateEmbeddingGenerator();
        var startTs = DateTimeOffset.UtcNow;
        var inputs = chunks.Select(c => c.Text).ToList();
        var embeddings = await GenerateEmbeddingsBatchedAsync(embedder, inputs, blobName, cancellationToken).ConfigureAwait(false);
        DataAiTelemetry.EmbeddingLatencyMs.Record((DateTimeOffset.UtcNow - startTs).TotalMilliseconds, new KeyValuePair<string, object?>("chunks", chunks.Count));

        // 5) Build IndexDocument batch
        var documentId = NormalizeDocumentId(blobName);
        var source = blobMetadata?.GetValueOrDefault("source") ?? InferSourceFromBlobName(blobName);
        var lastModified = DateTimeOffset.UtcNow;

        // ACL trimming: securityIds are populated by the Graph fetcher (comma-separated).
        // For non-Graph sources (afs, sqlmi, dataverse) the value is absent -> default to ["__org__"]
        // so the document is visible to authenticated tenant members but not anonymous callers.
        var securityIdsRaw = blobMetadata?.GetValueOrDefault("securityIds");
        var securityIds = string.IsNullOrWhiteSpace(securityIdsRaw)
            ? new[] { "__org__" }
            : securityIdsRaw.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        var docs = new List<IndexDocument>(chunks.Count);
        for (var i = 0; i < chunks.Count; i++)
        {
            var chunk = chunks[i];
            var emb = embeddings[i];
            docs.Add(new IndexDocument
            {
                Id = $"{documentId}-{chunk.Index}",
                DocumentId = documentId,
                Title = chunk.HeadingPath.Length > 0 ? chunk.HeadingPath : Path.GetFileNameWithoutExtension(blobName),
                Content = chunk.Text,
                ContentVector = emb.Vector.ToArray(),
                Source = source,
                SourcePath = blobName,
                Page = 0,
                ChunkIndex = chunk.Index,
                LastModified = lastModified,
                Metadata = blobMetadata is null
                    ? "{}"
                    : JsonSerializer.Serialize(blobMetadata),
                SecurityIds = securityIds,
            });
        }

        // 6) Upsert to AI Search
        var batch = IndexDocumentsBatch.MergeOrUpload(docs);
        var indexSw = System.Diagnostics.Stopwatch.StartNew();
        var response = await _search.IndexDocumentsAsync(
            batch,
            new IndexDocumentsOptions { ThrowOnAnyError = true },
            cancellationToken).ConfigureAwait(false);
        indexSw.Stop();
        DataAiTelemetry.IndexLatencyMs.Record(indexSw.ElapsedMilliseconds, new KeyValuePair<string, object?>("source", source));

        DataAiTelemetry.ChunksIndexed.Add(docs.Count, new KeyValuePair<string, object?>("source", source));
        _logger.LogInformation("Indexed {Count} chunks for {Blob} (source={Source}).", docs.Count, blobName, source);

        return docs.Count;
    }

    private static string InferSourceFromBlobName(string path)
    {
        var first = path.Split('/', 2)[0];
        return string.IsNullOrEmpty(first) ? "unknown" : first;
    }

    // Chunks per embedding request. Kept conservative so a single batch stays well under the
    // embedding deployment's per-minute token budget; larger files simply use more batches.
    private const int EmbeddingBatchSize = 32;
    private const int MaxEmbeddingRetries = 6;

    private async Task<IReadOnlyList<Embedding<float>>> GenerateEmbeddingsBatchedAsync(
        IEmbeddingGenerator<string, Embedding<float>> embedder,
        List<string> inputs,
        string blobName,
        CancellationToken cancellationToken)
    {
        var results = new List<Embedding<float>>(inputs.Count);

        for (var offset = 0; offset < inputs.Count; offset += EmbeddingBatchSize)
        {
            var batch = inputs.Skip(offset).Take(EmbeddingBatchSize).ToList();

            for (var attempt = 1; ; attempt++)
            {
                try
                {
                    var batchEmbeddings = await embedder.GenerateAsync(batch, cancellationToken: cancellationToken).ConfigureAwait(false);
                    results.AddRange(batchEmbeddings);
                    break;
                }
                catch (ClientResultException ex) when (ex.Status == 429 && attempt <= MaxEmbeddingRetries)
                {
                    var delay = GetEmbeddingRetryDelay(ex, attempt);
                    _logger.LogWarning(
                        "Embedding batch for {Blob} throttled (429); attempt {Attempt}/{Max}, retrying in {Seconds}s.",
                        blobName, attempt, MaxEmbeddingRetries, delay.TotalSeconds);
                    await Task.Delay(delay, cancellationToken).ConfigureAwait(false);
                }
            }
        }

        return results;
    }

    private static TimeSpan GetEmbeddingRetryDelay(ClientResultException ex, int attempt)
    {
        // Honor the service-provided Retry-After header when present.
        var response = ex.GetRawResponse();
        if (response is not null &&
            response.Headers.TryGetValue("retry-after", out var retryAfter) &&
            int.TryParse(retryAfter, out var seconds) &&
            seconds > 0)
        {
            return TimeSpan.FromSeconds(seconds);
        }

        // Otherwise exponential backoff capped at 60s.
        var backoff = Math.Min(60, (int)Math.Pow(2, attempt) * 2);
        return TimeSpan.FromSeconds(backoff);
    }

    private static string NormalizeDocumentId(string blobName)
    {
        Span<char> buf = stackalloc char[blobName.Length];
        for (var i = 0; i < blobName.Length; i++)
        {
            var ch = blobName[i];
            buf[i] = char.IsLetterOrDigit(ch) || ch is '-' or '_' ? ch : '_';
        }
        return new string(buf).TrimStart('_');
    }
}

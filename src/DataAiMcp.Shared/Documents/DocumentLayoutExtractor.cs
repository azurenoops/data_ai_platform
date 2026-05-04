using Azure;
using Azure.AI.DocumentIntelligence;
using DataAiMcp.Shared.Auth;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace DataAiMcp.Shared.Documents;

/// <summary>
/// Calls Azure Document Intelligence layout model and returns markdown + page metadata.
/// </summary>
public sealed class DocumentLayoutExtractor
{
    private readonly DocumentIntelligenceClient _client;
    private readonly ILogger<DocumentLayoutExtractor> _logger;

    public DocumentLayoutExtractor(
        AzureCredentialFactory credentialFactory,
        IOptions<DocumentIntelligenceOptions> options,
        ILogger<DocumentLayoutExtractor> logger)
    {
        var endpoint = new Uri(options.Value.Endpoint);
        _client = new DocumentIntelligenceClient(endpoint, credentialFactory.Credential);
        _logger = logger;
    }

    public async Task<DocumentLayoutResult> ExtractAsync(Stream content, CancellationToken cancellationToken)
    {
        await using var ms = new MemoryStream();
        await content.CopyToAsync(ms, cancellationToken).ConfigureAwait(false);
        ms.Position = 0;
        var binary = BinaryData.FromStream(ms);

        var operation = await _client.AnalyzeDocumentAsync(
            WaitUntil.Completed,
            modelId: "prebuilt-layout",
            bytesSource: binary,
            outputContentFormat: DocumentContentFormat.Markdown,
            cancellationToken: cancellationToken).ConfigureAwait(false);

        var result = operation.Value;
        _logger.LogInformation("DocIntel extracted {Pages} pages, {Chars} chars.", result.Pages?.Count ?? 0, result.Content?.Length ?? 0);

        return new DocumentLayoutResult(
            result.Content ?? string.Empty,
            result.Pages?.Count ?? 0);
    }
}

public sealed record DocumentLayoutResult(string Markdown, int PageCount);

public sealed class DocumentIntelligenceOptions
{
    public const string SectionName = "DocumentIntelligence";

    public string Endpoint { get; set; } = "";
}

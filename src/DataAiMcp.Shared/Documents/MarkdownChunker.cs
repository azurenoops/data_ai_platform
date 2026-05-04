using Markdig;
using Markdig.Syntax;
using Microsoft.ML.Tokenizers;

namespace DataAiMcp.Shared.Documents;

/// <summary>
/// Heading-aware markdown chunker. Splits documents on heading boundaries and re-emits
/// paragraph-grouped chunks of approximately <see cref="ChunkerOptions.TargetTokens"/>
/// tokens with the configured overlap. Token counts use the cl100k_base tokenizer
/// (compatible with text-embedding-3-large).
/// </summary>
public sealed class MarkdownChunker
{
    private readonly ChunkerOptions _options;
    private readonly Tokenizer _tokenizer;
    private readonly MarkdownPipeline _pipeline;

    public MarkdownChunker(ChunkerOptions? options = null)
    {
        _options = options ?? new ChunkerOptions();
        _tokenizer = TiktokenTokenizer.CreateForEncoding("cl100k_base");
        _pipeline = new MarkdownPipelineBuilder().Build();
    }

    public IReadOnlyList<MarkdownChunk> Chunk(string markdown)
    {
        if (string.IsNullOrWhiteSpace(markdown))
        {
            return Array.Empty<MarkdownChunk>();
        }

        var doc = Markdown.Parse(markdown, _pipeline);
        var sections = SplitSections(doc, markdown);

        var chunks = new List<MarkdownChunk>();
        var index = 0;
        foreach (var section in sections)
        {
            foreach (var chunkText in PackParagraphs(section.Text))
            {
                chunks.Add(new MarkdownChunk(index++, section.HeadingPath, chunkText));
            }
        }

        return chunks;
    }

    private List<Section> SplitSections(MarkdownDocument doc, string source)
    {
        var sections = new List<Section>();
        var headingStack = new List<string>(8);
        Section? current = null;

        foreach (var block in doc)
        {
            if (block is HeadingBlock heading)
            {
                var level = heading.Level;
                while (headingStack.Count >= level && headingStack.Count > 0)
                {
                    headingStack.RemoveAt(headingStack.Count - 1);
                }
                var text = heading.Inline?.FirstChild?.ToString() ?? string.Empty;
                headingStack.Add(text);

                current = new Section(string.Join(" / ", headingStack), new System.Text.StringBuilder());
                sections.Add(current);
                current.Builder.Append(new string('#', level)).Append(' ').AppendLine(text);
                continue;
            }

            current ??= new Section(string.Empty, new System.Text.StringBuilder());
            if (sections.Count == 0) sections.Add(current);

            var span = source.AsSpan(block.Span.Start, block.Span.Length);
            current.Builder.AppendLine(span.ToString());
            current.Builder.AppendLine();
        }

        return sections.Select(s => new Section(s.HeadingPath, s.Builder)).ToList();
    }

    private IEnumerable<string> PackParagraphs(string sectionText)
    {
        if (string.IsNullOrWhiteSpace(sectionText)) yield break;
        var paragraphs = sectionText.Split(["\n\n"], StringSplitOptions.RemoveEmptyEntries);
        var buffer = new System.Text.StringBuilder();
        var bufferTokens = 0;
        var bufferParas = new List<string>();

        foreach (var para in paragraphs)
        {
            var paraTokens = CountTokens(para);
            if (bufferTokens + paraTokens > _options.TargetTokens && bufferTokens > 0)
            {
                yield return buffer.ToString().Trim();
                // overlap: keep tail paragraphs whose token sum <= overlap budget.
                var (tailText, tailTokens) = ComputeOverlap(bufferParas);
                buffer.Clear();
                buffer.Append(tailText);
                bufferTokens = tailTokens;
                bufferParas = bufferParas.Where(p => tailText.Contains(p, StringComparison.Ordinal)).ToList();
            }

            if (buffer.Length > 0) buffer.Append("\n\n");
            buffer.Append(para);
            bufferTokens += paraTokens;
            bufferParas.Add(para);
        }

        if (buffer.Length > 0)
        {
            yield return buffer.ToString().Trim();
        }
    }

    private (string Text, int Tokens) ComputeOverlap(List<string> paragraphs)
    {
        var sb = new System.Text.StringBuilder();
        var tokenSum = 0;
        for (var i = paragraphs.Count - 1; i >= 0; i--)
        {
            var t = CountTokens(paragraphs[i]);
            if (tokenSum + t > _options.OverlapTokens) break;
            tokenSum += t;
            sb.Insert(0, "\n\n");
            sb.Insert(0, paragraphs[i]);
        }
        return (sb.ToString(), tokenSum);
    }

    private int CountTokens(string text)
    {
        if (string.IsNullOrEmpty(text)) return 0;
        return _tokenizer.CountTokens(text);
    }

    private sealed record Section(string HeadingPath, System.Text.StringBuilder Builder)
    {
        public string Text => Builder.ToString();
    }
}

public sealed record MarkdownChunk(int Index, string HeadingPath, string Text);

public sealed class ChunkerOptions
{
    public int TargetTokens { get; init; } = 800;
    public int OverlapTokens { get; init; } = 100;
}

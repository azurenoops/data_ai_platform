using DataAiMcp.Shared.Documents;
using FluentAssertions;
using Xunit;

namespace DataAiMcp.Shared.Tests;

public sealed class MarkdownChunkerTests
{
    [Fact]
    public void EmptyMarkdown_returnsNoChunks()
    {
        var chunker = new MarkdownChunker();
        chunker.Chunk("").Should().BeEmpty();
    }

    [Fact]
    public void SingleSection_isEmittedAsAtLeastOneChunk()
    {
        var md = """
            # Title
            Some prose.
            
            Another paragraph.
            """;
        var chunks = new MarkdownChunker().Chunk(md);
        chunks.Should().NotBeEmpty();
        chunks[0].HeadingPath.Should().Be("Title");
    }

    [Fact]
    public void NestedHeadings_emitJoinedHeadingPaths()
    {
        var md = """
            # A
            
            ## B
            
            content under B
            
            ## C
            
            content under C
            """;
        var chunks = new MarkdownChunker().Chunk(md);
        chunks.Should().Contain(c => c.HeadingPath == "A / B");
        chunks.Should().Contain(c => c.HeadingPath == "A / C");
    }

    [Fact]
    public void LongSection_isSplitIntoMultipleChunks()
    {
        var paragraph = string.Join(" ", Enumerable.Repeat("token", 200));
        var sb = new System.Text.StringBuilder();
        sb.AppendLine("# Big");
        for (var i = 0; i < 10; i++)
        {
            sb.AppendLine();
            sb.AppendLine(paragraph);
        }
        var chunker = new MarkdownChunker(new ChunkerOptions { TargetTokens = 300, OverlapTokens = 50 });
        var chunks = chunker.Chunk(sb.ToString());
        chunks.Count.Should().BeGreaterThan(1);
    }
}

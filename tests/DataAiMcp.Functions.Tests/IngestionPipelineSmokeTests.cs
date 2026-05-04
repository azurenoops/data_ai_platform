using DataAiMcp.Shared.Documents;
using FluentAssertions;
using Xunit;

namespace DataAiMcp.Functions.Tests;

/// <summary>
/// Compile-level smoke for the Functions project's reference closure. Replace with a full
/// pipeline test (Azurite + WireMock-stubbed Search/DI/Foundry) once the local emulator is wired.
/// </summary>
public sealed class IngestionPipelineSmokeTests
{
    [Fact]
    public void MarkdownChunker_canBeConstructed()
    {
        var chunker = new MarkdownChunker();
        chunker.Should().NotBeNull();
    }
}

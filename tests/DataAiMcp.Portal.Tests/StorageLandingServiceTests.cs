using System.Text;
using DataAiMcp.Portal.Models;
using DataAiMcp.Portal.Services;
using FluentAssertions;
using Microsoft.Extensions.Options;
using NSubstitute;
using Xunit;

namespace DataAiMcp.Portal.Tests;

public sealed class StorageLandingServiceTests
{
    [Fact]
    public async Task UploadAsync_NormalizesFolderAndFileName()
    {
        var adapter = Substitute.For<IBlobStorageAdapter>();
        var options = Options.Create(new PortalOptions
        {
            LandingContainerName = "landing",
            StorageAccountUrl = "https://storage",
            McpBaseUrl = "https://example",
            McpAudience = "api://example",
            SubscriptionId = "sub",
            ResourceGroupName = "rg",
            DataFactoryName = "adf",
            SqlPipelineName = "pipeline",
        });

        var sut = new StorageLandingService(options, adapter);
        await using var stream = new MemoryStream(Encoding.UTF8.GetBytes("demo"));

        var path = await sut.UploadAsync("/tmp/source/report.xlsx", " /demo/manual-drop/ ", stream, CancellationToken.None);

        path.Should().Be("demo/manual-drop/report.xlsx");
        await adapter.Received(1).UploadAsync(
            "landing",
            "demo/manual-drop/report.xlsx",
            Arg.Any<Stream>(),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task UploadAsync_UsesRootWhenFolderIsEmpty()
    {
        var adapter = Substitute.For<IBlobStorageAdapter>();
        var options = Options.Create(new PortalOptions
        {
            LandingContainerName = "landing",
            StorageAccountUrl = "https://storage",
            McpBaseUrl = "https://example",
            McpAudience = "api://example",
            SubscriptionId = "sub",
            ResourceGroupName = "rg",
            DataFactoryName = "adf",
            SqlPipelineName = "pipeline",
        });

        var sut = new StorageLandingService(options, adapter);
        await using var stream = new MemoryStream(Encoding.UTF8.GetBytes("demo"));

        var path = await sut.UploadAsync("notes.docx", "  ", stream, CancellationToken.None);

        path.Should().Be("notes.docx");
        await adapter.Received(1).UploadAsync(
            "landing",
            "notes.docx",
            Arg.Any<Stream>(),
            Arg.Any<CancellationToken>());
    }
}

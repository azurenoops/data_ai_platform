using System.Net;
using System.Net.Http;
using System.Text;
using DataAiMcp.Portal.Models;
using DataAiMcp.Portal.Services;
using DataAiMcp.Portal.Tests.TestDoubles;
using FluentAssertions;
using Microsoft.Extensions.Options;
using NSubstitute;
using Xunit;

namespace DataAiMcp.Portal.Tests;

public sealed class DataFactoryServiceTests
{
    [Fact]
    public async Task StartPipelineRunAsync_UsesExpectedEndpointAndReturnsRunId()
    {
        var handler = new CapturingHttpMessageHandler();
        handler.Enqueue(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent("{\"runId\":\"run-123\"}", Encoding.UTF8, "application/json"),
        });

        var tokenProvider = Substitute.For<IAzureManagementTokenProvider>();
        tokenProvider.GetAccessTokenAsync(Arg.Any<CancellationToken>()).Returns("token-abc");

        var service = CreateService(handler, tokenProvider);

        var runId = await service.StartPipelineRunAsync(CancellationToken.None);

        runId.Should().Be("run-123");
        handler.Requests.Should().HaveCount(1);
        handler.Requests[0].Method.Should().Be(HttpMethod.Post);
        handler.Requests[0].RequestUri!.ToString()
            .Should().Be("https://management.azure.com/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.DataFactory/factories/adf-1/pipelines/pl_sql/createRun?api-version=2018-06-01");
        var authHeader = handler.Requests[0].Headers.Authorization;
        authHeader.Should().NotBeNull();
        authHeader!.Scheme.Should().Be("Bearer");
        authHeader.Parameter.Should().Be("token-abc");
    }

    [Fact]
    public async Task GetPipelineRunAsync_ParsesRunSummary()
    {
        var handler = new CapturingHttpMessageHandler();
        handler.Enqueue(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent("{\"runId\":\"run-77\",\"status\":\"Succeeded\",\"runStart\":\"2026-06-17T12:00:00Z\",\"runEnd\":\"2026-06-17T12:00:30Z\",\"message\":\"ok\"}", Encoding.UTF8, "application/json"),
        });

        var tokenProvider = Substitute.For<IAzureManagementTokenProvider>();
        tokenProvider.GetAccessTokenAsync(Arg.Any<CancellationToken>()).Returns("token-abc");

        var service = CreateService(handler, tokenProvider);
        var run = await service.GetPipelineRunAsync("run-77", CancellationToken.None);

        run.RunId.Should().Be("run-77");
        run.Status.Should().Be("Succeeded");
        run.RunStart.Should().NotBeNull();
        run.RunEnd.Should().NotBeNull();
        run.Message.Should().Be("ok");

        handler.Requests.Should().HaveCount(1);
        handler.Requests[0].Method.Should().Be(HttpMethod.Get);
        handler.Requests[0].RequestUri!.ToString()
            .Should().Be("https://management.azure.com/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.DataFactory/factories/adf-1/pipelineruns/run-77?api-version=2018-06-01");
    }

    [Fact]
    public async Task GetCopyActivitySummariesAsync_FiltersAndSortsCopyTableActivities()
    {
        var handler = new CapturingHttpMessageHandler();
        handler.Enqueue(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(
                "{\"value\":[" +
                "{\"activityName\":\"CopyTable\",\"status\":\"Succeeded\",\"output\":{\"rowsCopied\":1200,\"filesWritten\":1,\"dataRead\":1000}}," +
                "{\"activityName\":\"OtherActivity\",\"status\":\"Succeeded\",\"output\":{\"rowsCopied\":9999,\"filesWritten\":1,\"dataRead\":9999}}," +
                "{\"activityName\":\"CopyTable\",\"status\":\"Succeeded\",\"output\":{\"rowsCopied\":5000,\"filesWritten\":1,\"dataRead\":2000}}" +
                "]}",
                Encoding.UTF8,
                "application/json"),
        });

        var tokenProvider = Substitute.For<IAzureManagementTokenProvider>();
        tokenProvider.GetAccessTokenAsync(Arg.Any<CancellationToken>()).Returns("token-abc");

        var service = CreateService(handler, tokenProvider);
        var summaries = await service.GetCopyActivitySummariesAsync("run-1", CancellationToken.None);

        summaries.Should().HaveCount(2);
        summaries[0].RowsCopied.Should().Be(5000);
        summaries[1].RowsCopied.Should().Be(1200);

        handler.Requests.Should().HaveCount(1);
        handler.Requests[0].Method.Should().Be(HttpMethod.Post);
        handler.Requests[0].RequestUri!.ToString()
            .Should().Be("https://management.azure.com/subscriptions/sub-1/resourceGroups/rg-1/providers/Microsoft.DataFactory/factories/adf-1/queryActivityruns?api-version=2018-06-01");
    }

    private static DataFactoryService CreateService(CapturingHttpMessageHandler handler, IAzureManagementTokenProvider tokenProvider)
    {
        var httpClient = new HttpClient(handler);
        var options = Options.Create(new PortalOptions
        {
            SubscriptionId = "sub-1",
            ResourceGroupName = "rg-1",
            DataFactoryName = "adf-1",
            SqlPipelineName = "pl_sql",
            McpBaseUrl = "https://example",
            McpAudience = "api://example",
            StorageAccountUrl = "https://storage",
            LandingContainerName = "landing",
        });

        return new DataFactoryService(httpClient, options, tokenProvider);
    }
}

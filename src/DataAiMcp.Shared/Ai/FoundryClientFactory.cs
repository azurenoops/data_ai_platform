using Azure.AI.OpenAI;
using DataAiMcp.Shared.Auth;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Options;

namespace DataAiMcp.Shared.Ai;

/// <summary>
/// Builds Microsoft.Extensions.AI clients backed by an Azure AI Foundry / Azure OpenAI deployment.
/// One factory is registered per process; clients are cached as singletons via DI registration.
/// </summary>
public sealed class FoundryClientFactory
{
    private readonly AzureOpenAIClient _client;
    private readonly FoundryOptions _options;

    public FoundryClientFactory(AzureCredentialFactory credentialFactory, IOptions<FoundryOptions> options)
    {
        _options = options.Value;
        _client = new AzureOpenAIClient(new Uri(_options.Endpoint), credentialFactory.Credential);
    }

    public IChatClient CreateChatClient(string? deploymentOverride = null)
    {
        var deployment = deploymentOverride ?? _options.ChatDeployment;
        return _client.GetChatClient(deployment).AsIChatClient();
    }

    public IEmbeddingGenerator<string, Embedding<float>> CreateEmbeddingGenerator(string? deploymentOverride = null)
    {
        var deployment = deploymentOverride ?? _options.EmbeddingDeployment;
        return _client.GetEmbeddingClient(deployment).AsIEmbeddingGenerator();
    }
}

public sealed class FoundryOptions
{
    public const string SectionName = "Foundry";

    /// <summary>Account-level endpoint, e.g. <c>https://my-foundry.cognitiveservices.azure.com/</c>.</summary>
    public string Endpoint { get; set; } = "";

    /// <summary>Project-scoped endpoint, used for project-aware features (agents, threads).</summary>
    public string ProjectEndpoint { get; set; } = "";

    public string ChatDeployment { get; set; } = "gpt-4o";
    public string ChatMiniDeployment { get; set; } = "gpt-4o-mini";
    public string EmbeddingDeployment { get; set; } = "text-embedding-3-large";
}

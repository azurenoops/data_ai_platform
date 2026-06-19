using System.Text;
using System.Text.Json;
using DataAiMcp.Shared.Ai;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;

namespace DataAiMcp.Portal.Services;

/// <summary>
/// Synthesizes a grounded, natural-language answer from the passages returned by
/// <c>search_documents</c>, mimicking how an MCP-enabled chat assistant would respond.
/// Returns <c>null</c> when no chat model is reachable so callers can fall back to
/// showing the retrieved passages only.
/// </summary>
public interface IChatAnswerService
{
    Task<string?> SynthesizeAsync(string question, string searchPayloadJson, CancellationToken cancellationToken);
}

public sealed class ChatAnswerService : IChatAnswerService
{
    private const string SystemPrompt =
        "You are a grounded assistant for an internal data + AI platform. " +
        "Answer the user's question using ONLY the provided context passages. " +
        "Be concise (a short paragraph or a few bullet points). " +
        "Cite the source titles you relied on in square brackets, e.g. [Fleet Ops Q3]. " +
        "If the context does not contain the answer, say you don't have enough indexed " +
        "information yet and suggest rephrasing or removing the source filter. " +
        "Never invent facts that are not in the context.";

    private readonly FoundryClientFactory _foundryClientFactory;
    private readonly ILogger<ChatAnswerService> _logger;

    public ChatAnswerService(FoundryClientFactory foundryClientFactory, ILogger<ChatAnswerService> logger)
    {
        _foundryClientFactory = foundryClientFactory;
        _logger = logger;
    }

    public async Task<string?> SynthesizeAsync(string question, string searchPayloadJson, CancellationToken cancellationToken)
    {
        var context = BuildContext(searchPayloadJson);
        if (string.IsNullOrWhiteSpace(context))
        {
            return null;
        }

        try
        {
            var chatClient = _foundryClientFactory.CreateChatClient();
            var messages = new List<ChatMessage>
            {
                new(ChatRole.System, SystemPrompt),
                new(ChatRole.User, $"Question: {question}\n\nContext passages:\n{context}"),
            };

            var response = await chatClient.GetResponseAsync(
                messages,
                new ChatOptions { Temperature = 0.2f, MaxOutputTokens = 600 },
                cancellationToken).ConfigureAwait(false);

            var text = response.Text?.Trim();
            return string.IsNullOrWhiteSpace(text) ? null : text;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Chat synthesis failed; falling back to retrieved passages only.");
            return null;
        }
    }

    private static string BuildContext(string searchPayloadJson)
    {
        if (string.IsNullOrWhiteSpace(searchPayloadJson))
        {
            return string.Empty;
        }

        JsonElement root;
        try
        {
            using var doc = JsonDocument.Parse(searchPayloadJson);
            root = doc.RootElement.Clone();
        }
        catch (JsonException)
        {
            return string.Empty;
        }

        if (root.ValueKind != JsonValueKind.Array)
        {
            return string.Empty;
        }

        var builder = new StringBuilder();
        var index = 1;
        foreach (var hit in root.EnumerateArray())
        {
            var title = GetString(hit, "title", "Title");
            var source = GetString(hit, "source", "Source");
            var snippet = GetString(hit, "snippet", "Snippet");
            if (string.IsNullOrWhiteSpace(snippet))
            {
                continue;
            }

            if (snippet.Length > 700)
            {
                snippet = snippet[..700];
            }

            var label = string.IsNullOrWhiteSpace(title) ? $"passage {index}" : title;
            builder.Append('[').Append(index).Append("] ");
            if (!string.IsNullOrWhiteSpace(source))
            {
                builder.Append('(').Append(source).Append(") ");
            }

            builder.Append(label).Append(": ").Append(snippet).Append('\n');
            index++;
        }

        return builder.ToString();
    }

    private static string GetString(JsonElement element, params string[] names)
    {
        foreach (var name in names)
        {
            if (element.ValueKind == JsonValueKind.Object &&
                element.TryGetProperty(name, out var value) &&
                value.ValueKind == JsonValueKind.String)
            {
                return value.GetString() ?? string.Empty;
            }
        }

        return string.Empty;
    }
}

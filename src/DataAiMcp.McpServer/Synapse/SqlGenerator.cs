using System.Text;
using DataAiMcp.Shared.Ai;
using DataAiMcp.Shared.Models;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;

namespace DataAiMcp.McpServer.Synapse;

/// <summary>
/// Generates a single read-only SELECT statement for a target dataset by prompting the chat model.
/// Output is post-validated by <see cref="SynapseQueryClient.ExecuteAsync"/>.
/// </summary>
public sealed class SqlGenerator
{
    private readonly FoundryClientFactory _foundry;
    private readonly ILogger<SqlGenerator> _logger;

    public SqlGenerator(FoundryClientFactory foundry, ILogger<SqlGenerator> logger)
    {
        _foundry = foundry;
        _logger = logger;
    }

    public async Task<string> GenerateAsync(DatasetDescriptor dataset, string question, CancellationToken cancellationToken)
    {
        var schema = new StringBuilder();
        schema.Append("View: ").AppendLine(dataset.ViewName);
        schema.AppendLine("Columns:");
        foreach (var col in dataset.Columns)
        {
            schema.Append(" - ").Append(col.Name).Append(' ').Append(col.DataType);
            if (!string.IsNullOrEmpty(col.Description))
            {
                schema.Append(" -- ").Append(col.Description);
            }
            schema.AppendLine();
        }

        var systemPrompt = $"""
            You are a T-SQL expert generating queries for Azure Synapse serverless SQL.
            Strict rules:
            - Output a single SELECT statement only - no comments, no DDL, no semicolons except at the end (optional), no temp tables, no procedures.
            - Use only the view {dataset.ViewName} and the columns listed below.
            - Use TOP (n) to limit rows; never return more than 200 rows.
            - Do not invent columns or tables.
            - Do not include any prose, only the SQL.
            
            {schema}
            """;

        var chat = _foundry.CreateChatClient();
        var messages = new[]
        {
            new ChatMessage(ChatRole.System, systemPrompt),
            new ChatMessage(ChatRole.User, question),
        };

        var response = await chat.GetResponseAsync(messages, new ChatOptions { Temperature = 0.0f }, cancellationToken).ConfigureAwait(false);
        var text = response.Text?.Trim() ?? "";

        // strip code fences if present
        if (text.StartsWith("```", StringComparison.Ordinal))
        {
            text = StripFence(text);
        }

        _logger.LogInformation("Generated SQL for {Dataset}: {Sql}", dataset.Name, text);
        return text;
    }

    private static string StripFence(string text)
    {
        var firstNewline = text.IndexOf('\n');
        if (firstNewline < 0) return text;
        var body = text[(firstNewline + 1)..];
        var lastFence = body.LastIndexOf("```", StringComparison.Ordinal);
        return lastFence >= 0 ? body[..lastFence].Trim() : body.Trim();
    }
}

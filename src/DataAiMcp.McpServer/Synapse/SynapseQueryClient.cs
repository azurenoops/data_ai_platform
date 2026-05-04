using System.Data;
using DataAiMcp.Shared.Auth;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace DataAiMcp.McpServer.Synapse;

/// <summary>
/// Executes T-SQL against the Synapse <c>serverless</c> SQL endpoint using AAD tokens.
/// All access is scoped to the curated views — execution rejects anything that mutates state.
/// </summary>
public sealed class SynapseQueryClient
{
    private readonly AzureCredentialFactory _credentials;
    private readonly SynapseOptions _options;
    private readonly ILogger<SynapseQueryClient> _logger;

    public SynapseQueryClient(
        AzureCredentialFactory credentials,
        IOptions<SynapseOptions> options,
        ILogger<SynapseQueryClient> logger)
    {
        _credentials = credentials;
        _options = options.Value;
        _logger = logger;
    }

    public async Task<SynapseResult> ExecuteAsync(string sql, CancellationToken cancellationToken)
    {
        ValidateReadOnly(sql);

        var connectionString = $"Server={_options.ServerlessSqlEndpoint};Database={_options.Database};Encrypt=True;";
        await using var connection = new SqlConnection(connectionString);

        var token = await _credentials.Credential.GetTokenAsync(
            new Azure.Core.TokenRequestContext(["https://database.windows.net/.default"]),
            cancellationToken).ConfigureAwait(false);
        connection.AccessToken = token.Token;

        await connection.OpenAsync(cancellationToken).ConfigureAwait(false);

        await using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.CommandType = CommandType.Text;
        command.CommandTimeout = _options.QueryTimeoutSeconds;

        await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
        var rows = new List<IReadOnlyDictionary<string, object?>>();
        var truncated = false;

        while (await reader.ReadAsync(cancellationToken).ConfigureAwait(false))
        {
            if (rows.Count >= _options.MaxRows)
            {
                truncated = true;
                break;
            }

            var row = new Dictionary<string, object?>(reader.FieldCount, StringComparer.Ordinal);
            for (var i = 0; i < reader.FieldCount; i++)
            {
                row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
            }
            rows.Add(row);
        }

        _logger.LogInformation("Synapse query returned {Rows} rows (truncated={Truncated}).", rows.Count, truncated);
        return new SynapseResult(rows, truncated);
    }

    private static void ValidateReadOnly(string sql)
    {
        var normalized = sql.Trim();
        if (!normalized.StartsWith("SELECT", StringComparison.OrdinalIgnoreCase) &&
            !normalized.StartsWith("WITH", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Only read-only queries (SELECT/WITH) are permitted.");
        }
        var banned = new[] { ";--", "DELETE ", "UPDATE ", "INSERT ", "MERGE ", "DROP ", "TRUNCATE ", "ALTER ", "EXEC ", "EXECUTE ", "GRANT ", "REVOKE " };
        foreach (var b in banned)
        {
            if (normalized.Contains(b, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException($"Disallowed token in query: '{b.Trim()}'.");
            }
        }
    }
}

public sealed record SynapseResult(IReadOnlyList<IReadOnlyDictionary<string, object?>> Rows, bool Truncated);

public sealed class SynapseOptions
{
    public const string SectionName = "Synapse";

    public string ServerlessSqlEndpoint { get; set; } = "";
    public string Database { get; set; } = "master";
    public int MaxRows { get; set; } = 200;
    public int QueryTimeoutSeconds { get; set; } = 30;
}

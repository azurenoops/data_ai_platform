using System.ComponentModel;
using DataAiMcp.McpServer.Synapse;
using DataAiMcp.Shared.Models;
using Microsoft.Extensions.Options;
using ModelContextProtocol.Server;

namespace DataAiMcp.McpServer.Tools;

[McpServerToolType]
public sealed class StructuredTools
{
    private readonly SynapseQueryClient _synapse;
    private readonly SqlGenerator _sql;
    private readonly DatasetCatalogOptions _catalog;

    public StructuredTools(SynapseQueryClient synapse, SqlGenerator sql, IOptions<DatasetCatalogOptions> catalog)
    {
        _synapse = synapse;
        _sql = sql;
        _catalog = catalog.Value;
    }

    [McpServerTool(Name = "query_structured_data")]
    [Description("Translate a natural-language question into T-SQL against the curated Synapse views and return the rows + the generated SQL for inspection.")]
    public async Task<StructuredQueryResult> QueryStructuredDataAsync(
        [Description("Natural-language question.")] string question,
        [Description("Optional dataset name (e.g. 'dataverse_account', 'sqlmi_orders'). When omitted, the model picks one.")] string? dataset = null,
        CancellationToken cancellationToken = default)
    {
        var target = ResolveDataset(dataset, question);
        var generated = await _sql.GenerateAsync(target, question, cancellationToken).ConfigureAwait(false);
        var rows = await _synapse.ExecuteAsync(generated, cancellationToken).ConfigureAwait(false);
        return new StructuredQueryResult
        {
            GeneratedSql = generated,
            Rows = rows.Rows,
            RowCount = rows.Rows.Count,
            Truncated = rows.Truncated ? "Result was truncated to the configured row cap." : null,
        };
    }

    [McpServerTool(Name = "describe_dataset")]
    [Description("Return the curated catalog entry for one or all datasets (name, view, columns, sample questions).")]
    public IReadOnlyList<DatasetDescriptor> DescribeDataset(
        [Description("Optional dataset name. Omit to list all.")] string? name = null)
    {
        if (string.IsNullOrEmpty(name))
        {
            return _catalog.Datasets;
        }
        return _catalog.Datasets
            .Where(d => string.Equals(d.Name, name, StringComparison.OrdinalIgnoreCase))
            .ToArray();
    }

    private DatasetDescriptor ResolveDataset(string? requested, string question)
    {
        if (!string.IsNullOrEmpty(requested))
        {
            var match = _catalog.Datasets.FirstOrDefault(d => string.Equals(d.Name, requested, StringComparison.OrdinalIgnoreCase));
            if (match is not null) return match;
        }
        // crude heuristic: pick the dataset whose description shares the most keywords with the question.
        var bestMatch = _catalog.Datasets
            .Select(d => new
            {
                Dataset = d,
                Score = (d.Name + " " + d.Description).Split(' ', StringSplitOptions.RemoveEmptyEntries)
                    .Count(token => question.Contains(token, StringComparison.OrdinalIgnoreCase)),
            })
            .OrderByDescending(x => x.Score)
            .FirstOrDefault();
        return bestMatch?.Dataset ?? _catalog.Datasets.First();
    }
}

public sealed class DatasetCatalogOptions
{
    public List<DatasetDescriptor> Datasets { get; set; } = new();
}

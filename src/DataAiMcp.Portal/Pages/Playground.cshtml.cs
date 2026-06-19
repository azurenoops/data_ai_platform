using DataAiMcp.Portal.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace DataAiMcp.Portal.Pages;

public class PlaygroundModel : PageModel
{
    private readonly IMcpToolService _mcpToolService;
    private readonly IChatAnswerService _chatAnswerService;

    public PlaygroundModel(IMcpToolService mcpToolService, IChatAnswerService chatAnswerService)
    {
        _mcpToolService = mcpToolService;
        _chatAnswerService = chatAnswerService;
    }

    [BindProperty]
    public string ToolName { get; set; } = "list_sources";

    [BindProperty]
    public string Query { get; set; } = "fleet operations quarterly readiness summary";

    [BindProperty]
    public string Question { get; set; } = "Which projects are over budget where SpentUsd > BudgetUsd? Return ProjectName, Status, BudgetUsd, SpentUsd ordered by SpentUsd descending. Top 25.";

    [BindProperty]
    public string Dataset { get; set; } = string.Empty;

    [BindProperty]
    public string DocumentId { get; set; } = string.Empty;

    [BindProperty]
    public string Source { get; set; } = string.Empty;

    [BindProperty]
    public int Top { get; set; } = 5;

    public string ResultPayload { get; private set; } = string.Empty;

    public string ResultMessage { get; private set; } = string.Empty;

    public bool IsSuccess { get; private set; }

    public static IReadOnlyList<PromptCategory> PromptCategories { get; } = BuildPromptCategories();

    public void OnGet()
    {
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        try
        {
            var args = BuildArguments();
            ResultPayload = await _mcpToolService.ExecuteToolAsync(ToolName, args, cancellationToken).ConfigureAwait(false);
            IsSuccess = true;
            ResultMessage = $"{ToolName} completed.";
        }
        catch (Exception ex)
        {
            IsSuccess = false;
            ResultMessage = $"Tool execution failed: {ex.Message}";
        }

        return Page();
    }

    public async Task<IActionResult> OnPostAskAsync([FromBody] AskRequest request, CancellationToken cancellationToken)
    {
        var question = request?.Question?.Trim();
        if (string.IsNullOrWhiteSpace(question))
        {
            return new JsonResult(new { ok = false, error = "Ask a question first." });
        }

        var top = Math.Clamp(request!.Top ?? 5, 1, 8);
        var args = new Dictionary<string, object?>
        {
            ["query"] = question,
            ["top"] = top,
        };

        if (!string.IsNullOrWhiteSpace(request.Source))
        {
            args["source"] = request.Source.Trim();
        }

        try
        {
            var payload = await _mcpToolService
                .ExecuteToolAsync("search_documents", args, cancellationToken)
                .ConfigureAwait(false);
            var answer = await _chatAnswerService
                .SynthesizeAsync(question, payload, cancellationToken)
                .ConfigureAwait(false);
            return new JsonResult(new { ok = true, answer, payload });
        }
        catch (Exception ex)
        {
            return new JsonResult(new { ok = false, error = ex.Message });
        }
    }

    private Dictionary<string, object?> BuildArguments()    {
        var args = new Dictionary<string, object?>();

        switch (ToolName)
        {
            case "search_documents":
                args["query"] = string.IsNullOrWhiteSpace(Query) ? "status" : Query;
                args["top"] = Top;
                if (!string.IsNullOrWhiteSpace(Source))
                {
                    args["source"] = Source;
                }

                break;

            case "query_structured_data":
                args["question"] = string.IsNullOrWhiteSpace(Question) ? "show 10 rows" : Question;
                if (!string.IsNullOrWhiteSpace(Dataset))
                {
                    args["dataset"] = Dataset;
                }

                break;

            case "describe_dataset":
                if (!string.IsNullOrWhiteSpace(Dataset))
                {
                    args["name"] = Dataset;
                }

                break;

            case "get_document":
                if (!string.IsNullOrWhiteSpace(DocumentId))
                {
                    args["documentId"] = DocumentId;
                }

                break;
        }

        return args;
    }

    private static IReadOnlyList<PromptCategory> BuildPromptCategories() =>
    [
        new("A", "Quick capability check",
            "Inspect what the server exposes. These run a single MCP tool directly.",
            null,
            [
                new("List available sources & document counts", "list_sources"),
                new("List structured datasets (views & columns)", "describe_dataset"),
            ]),
        new("B", "Document intelligence (unstructured RAG)",
            "Hybrid search over the manually curated document corpus (source = manual).",
            null,
            [
                new("Fleet ops quarterly: readiness improvements & recurring fault families", "search_documents",
                    Query: "fleet operations quarterly report readiness improvements recurring fault families", Source: "manual", Top: 5),
                new("Incidents: config drift / expired credentials root causes & corrective actions", "search_documents",
                    Query: "incidents config drift expired credentials root cause corrective actions", Source: "manual", Top: 5),
                new("Mission events: patterns by region and status", "search_documents",
                    Query: "mission event patterns by region and status anomalies", Source: "manual", Top: 5),
                new("Portfolio KPI: high burn-rate, high-risk programs", "search_documents",
                    Query: "portfolio programs high burn rate high risk level", Source: "manual", Top: 5),
            ]),
        new("C", "SQL-style dataset insights (sql-demo documents)",
            "Hybrid search over the tabular SQL exports ingested as spreadsheets (source = sql-demo). Sampled rows; use C2 for exact numbers.",
            null,
            [
                new("Projects over budget by region / sector", "search_documents",
                    Query: "projects over budget by region and sector", Source: "sql-demo", Top: 5),
                new("Work orders by severity & system area, hours open", "search_documents",
                    Query: "work orders by severity and system area highest hours open", Source: "sql-demo", Top: 5),
                new("Inspection findings: types that fail most", "search_documents",
                    Query: "inspection findings types that fail most counts hotspots", Source: "sql-demo", Top: 5),
                new("Telemetry: warning / critical health trends", "search_documents",
                    Query: "telemetry warning critical health state suspicious metrics", Source: "sql-demo", Top: 5),
            ]),
        new("C2", "Structured SQL dataset prompts (Synapse views)",
            "Natural-language → T-SQL over the Synapse 'datalake' views. Returns rows + the generated SQL. One dataset per query.",
            null,
            [
                new("Projects over budget (SpentUsd > BudgetUsd) by status", "query_structured_data",
                    Question: "Which projects are over budget where SpentUsd > BudgetUsd? Return ProjectName, Status, BudgetUsd, SpentUsd ordered by SpentUsd descending. Top 25.", Dataset: "projects"),
                new("Top severity / system-area open workload (WorkOrders)", "query_structured_data",
                    Question: "List the top Severity and SystemArea combinations by work order count and total HoursOpen. Return Severity, SystemArea, the count, and the summed HoursOpen ordered by summed HoursOpen descending. Top 15.", Dataset: "work_orders"),
                new("Inspection findings: failure counts by type", "query_structured_data",
                    Question: "How many findings have Result = 'Fail' grouped by FindingType? Return FindingType and the count ordered by count descending.", Dataset: "inspection_findings"),
                new("Telemetry: metrics with frequent critical health state", "query_structured_data",
                    Question: "Which MetricName values have the most readings with HealthState = 'critical'? Return MetricName and the count ordered by count descending. Top 15.", Dataset: "telemetry_readings"),
            ]),
        new("D", "Cross-source synthesis",
            "Multi-tool reasoning is performed by your LLM-enabled MCP client. These presets retrieve supporting context across all sources to seed that synthesis.",
            "Best run in an LLM MCP client; the preset gathers context only.",
            [
                new("Correlate mission anomalies with incident root causes", "search_documents",
                    Query: "mission event anomalies correlated with incident root causes risk drivers", Top: 8),
                new("30-day stabilization plan (portfolio + incidents + sql-demo)", "search_documents",
                    Query: "portfolio incidents sql-demo stabilization plan priorities risks", Top: 8),
            ]),
        new("E", "Executive brief",
            "Summarization prompts for an LLM-enabled MCP client. These presets retrieve the supporting evidence.",
            "Best run in an LLM MCP client; the preset gathers context only.",
            [
                new("Exec summary: operational risk, budget pressure, supplier performance", "search_documents",
                    Query: "executive summary operational risk budget pressure supplier performance", Top: 8),
                new("Top 10 actionable findings with owners & expected impact", "search_documents",
                    Query: "top actionable findings owners teams expected impact", Top: 10),
            ]),
    ];
}

public sealed record PromptCategory(
    string Code,
    string Title,
    string Description,
    string? Note,
    IReadOnlyList<PromptPreset> Prompts);

public sealed record PromptPreset(
    string Label,
    string Tool,
    string? Query = null,
    string? Question = null,
    string? Dataset = null,
    string? Source = null,
    int? Top = null);

public sealed record AskRequest(string? Question, string? Source, int? Top);

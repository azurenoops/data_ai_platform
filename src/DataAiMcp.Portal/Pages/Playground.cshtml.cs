using DataAiMcp.Portal.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace DataAiMcp.Portal.Pages;

public class PlaygroundModel : PageModel
{
    private readonly IMcpToolService _mcpToolService;

    public PlaygroundModel(IMcpToolService mcpToolService)
    {
        _mcpToolService = mcpToolService;
    }

    [BindProperty]
    public string ToolName { get; set; } = "list_sources";

    [BindProperty]
    public string Query { get; set; } = "navsea readiness summary";

    [BindProperty]
    public string Question { get; set; } = "Top 10 rows in sqlmi_orders";

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

    private Dictionary<string, object?> BuildArguments()
    {
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

            case "get_document":
                if (!string.IsNullOrWhiteSpace(DocumentId))
                {
                    args["documentId"] = DocumentId;
                }

                break;
        }

        return args;
    }
}

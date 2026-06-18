using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace DataAiMcp.Portal.Pages;

public class OnboardingWizardModel : PageModel
{
    [BindProperty]
    public string SourceType { get; set; } = "sharepoint";

    [BindProperty]
    public string Owner { get; set; } = string.Empty;

    [BindProperty]
    public string LocationHint { get; set; } = string.Empty;

    [BindProperty]
    public string ScheduleHint { get; set; } = string.Empty;

    [BindProperty]
    public string Notes { get; set; } = string.Empty;

    public List<string> Checklist { get; private set; } = new();

    public string RunbookPath { get; private set; } = "docs/INGESTION.md";

    public string ValidationMessage { get; private set; } = string.Empty;

    public bool IsValidInput { get; private set; }

    public void OnGet()
    {
    }

    public IActionResult OnPost()
    {
        Checklist = BuildChecklist(SourceType);
        RunbookPath = ResolveRunbook(SourceType);

        var missing = new List<string>();
        if (string.IsNullOrWhiteSpace(Owner))
        {
            missing.Add("data owner");
        }

        if (string.IsNullOrWhiteSpace(LocationHint))
        {
            missing.Add("source identifier");
        }

        if (SourceType is "sharepoint" or "onedrive" or "sqlmi" && string.IsNullOrWhiteSpace(ScheduleHint))
        {
            missing.Add("schedule");
        }

        if (missing.Count == 0)
        {
            IsValidInput = true;
            ValidationMessage = "Inputs look complete. Continue with the runbook path listed above.";
        }
        else
        {
            IsValidInput = false;
            ValidationMessage = "Missing required inputs: " + string.Join(", ", missing) + ".";
        }

        return Page();
    }

    private static List<string> BuildChecklist(string sourceType)
    {
        var common = new List<string>
        {
            "Confirm data owner approval and source boundaries.",
            "Validate portal environment settings (resource group, storage, pipeline names).",
            "Run a small test ingestion and verify results in Source Catalog and MCP Playground.",
        };

        return sourceType switch
        {
            "sharepoint" =>
            [
                "Capture approved SharePoint Drive IDs.",
                "Set SharePoint schedule and validate Graph permissions.",
                .. common,
            ],
            "onedrive" =>
            [
                "Capture approved OneDrive Drive IDs.",
                "Set OneDrive schedule and validate Graph permissions.",
                .. common,
            ],
            "sqlmi" =>
            [
                "Validate ADF linked service and SQL MI managed identity access.",
                "Confirm pipeline table list and schedule window.",
                .. common,
            ],
            "dataverse" =>
            [
                "Validate Synapse Link and Dataverse connectivity.",
                "Confirm expected entities and refresh cadence.",
                .. common,
            ],
            _ =>
            [
                "Define landing folder convention and source metadata.",
                "Upload one representative file for validation.",
                .. common,
            ],
        };
    }

    private static string ResolveRunbook(string sourceType)
    {
        return sourceType switch
        {
            "sharepoint" => "docs/ingestion/sharepoint-files.md",
            "onedrive" => "docs/ingestion/onedrive-files.md",
            "sqlmi" => "docs/ingestion/sql-managed-instance.md",
            "dataverse" => "docs/ingestion/dataverse.md",
            _ => "docs/ingestion/blob-drop.md",
        };
    }
}

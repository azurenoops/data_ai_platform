using DataAiMcp.Portal.Services;
using DataAiMcp.Shared.Ingestion;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.Identity.Web;
using System.ComponentModel.DataAnnotations;

namespace DataAiMcp.Portal.Pages.Admin;

/// <summary>
/// Sources administration page. Allows operators to view, add, enable/disable, and delete
/// data source configurations. The Page Model handles the UI logic; the actual
/// configurations are persisted to CosmosDB and processed by the DispatcherFunction.
/// </summary>
[Microsoft.AspNetCore.Authorization.Authorize]
public class SourcesModel : PageModel
{
    private readonly ISourceConfigurationService _sourceService;
    private readonly ILogger<SourcesModel> _logger;

    public SourcesModel(
        ISourceConfigurationService sourceService,
        ILogger<SourcesModel> logger)
    {
        _sourceService = sourceService;
        _logger = logger;
    }

    [BindProperty]
    public List<SourceConfiguration> Sources { get; set; } = new();

    [BindProperty]
    public List<SourceTypeInfo> SupportedSourceTypes { get; set; } = new();

    [BindProperty]
    public string? SelectedSourceType { get; set; }

    [BindProperty]
    public Dictionary<string, string> SourceSettings { get; set; } = new();

    [BindProperty]
    [Display(Name = "Display Name")]
    public string? DisplayName { get; set; }

    public string? SuccessMessage { get; set; }
    public string? ErrorMessage { get; set; }

    public async Task OnGetAsync(CancellationToken ct)
    {
        try
        {
            Sources = (await _sourceService.GetAllSourcesAsync(ct)).ToList();
            SupportedSourceTypes = _sourceService.GetSupportedSourceTypes().ToList();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error loading sources");
            ErrorMessage = "Failed to load sources. Please try again.";
        }
    }

    public async Task<IActionResult> OnPostAddSourceAsync(CancellationToken ct)
    {
        if (string.IsNullOrEmpty(SelectedSourceType))
        {
            ErrorMessage = "Please select a source type";
            return RedirectToPage();
        }

        try
        {
            // Collect settings from form
            var settings = new Dictionary<string, string>();
            var typeInfo = _sourceService.GetSupportedSourceTypes()
                .FirstOrDefault(t => t.SourceType == SelectedSourceType);

            if (typeInfo is null)
            {
                ErrorMessage = "Invalid source type";
                return RedirectToPage();
            }

            // Gather settings from request
            foreach (var setting in typeInfo.RequiredSettings.Union(typeInfo.OptionalSettings))
            {
                if (Request.Form.TryGetValue($"settings_{setting.Key}", out var value) && !string.IsNullOrWhiteSpace(value))
                {
                    settings[setting.Key] = value.ToString();
                }
            }

            var userOid = User.GetObjectId() ?? "unknown";
            var (isValid, source, errors) = await _sourceService.ValidateAndCreateAsync(
                SelectedSourceType, settings, DisplayName, userOid, ct);

            if (!isValid)
            {
                ErrorMessage = string.Join("; ", errors);
                return RedirectToPage();
            }

            SuccessMessage = $"Source '{source?.DisplayName}' created successfully. It will be processed on the next ingestion run.";
            _logger.LogInformation("Source added by {UserId}: {SourceId}", userOid, source?.Id);

            return RedirectToPage();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error adding source");
            ErrorMessage = "Failed to add source: " + ex.Message;
            return RedirectToPage();
        }
    }

    public async Task<IActionResult> OnPostToggleSourceAsync(string id, CancellationToken ct)
    {
        try
        {
            var source = await _sourceService.GetSourceByIdAsync(id, ct);
            if (source is null)
            {
                ErrorMessage = "Source not found";
                return RedirectToPage();
            }

            await _sourceService.ToggleSourceAsync(id, !source.Enabled, ct);
            SuccessMessage = $"Source '{source.DisplayName}' is now {(!source.Enabled ? "enabled" : "disabled")}.";
            _logger.LogInformation("Source toggled by {UserId}: {SourceId}", User.GetObjectId(), id);

            return RedirectToPage();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error toggling source");
            ErrorMessage = "Failed to toggle source: " + ex.Message;
            return RedirectToPage();
        }
    }

    public async Task<IActionResult> OnPostDeleteSourceAsync(string id, CancellationToken ct)
    {
        try
        {
            var source = await _sourceService.GetSourceByIdAsync(id, ct);
            if (source is null)
            {
                ErrorMessage = "Source not found";
                return RedirectToPage();
            }

            await _sourceService.DeleteSourceAsync(id, ct);
            SuccessMessage = $"Source '{source.DisplayName}' has been deleted.";
            _logger.LogInformation("Source deleted by {UserId}: {SourceId}", User.GetObjectId(), id);

            return RedirectToPage();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting source");
            ErrorMessage = "Failed to delete source: " + ex.Message;
            return RedirectToPage();
        }
    }
}

using DataAiMcp.Portal.Models;
using DataAiMcp.Portal.Services;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace DataAiMcp.Portal.Pages;

public class SourceCatalogModel : PageModel
{
    private readonly IMcpToolService _mcpToolService;

    public SourceCatalogModel(IMcpToolService mcpToolService)
    {
        _mcpToolService = mcpToolService;
    }

    public IReadOnlyList<SourceCatalogItem> Sources { get; private set; } = Array.Empty<SourceCatalogItem>();

    public IReadOnlyList<DatasetCatalogItem> Datasets { get; private set; } = Array.Empty<DatasetCatalogItem>();

    public string ErrorMessage { get; private set; } = string.Empty;

    public async Task OnGetAsync(CancellationToken cancellationToken)
    {
        try
        {
            var result = await _mcpToolService.GetSourceCatalogAsync(cancellationToken).ConfigureAwait(false);
            Sources = result.Sources;
            Datasets = result.Datasets;
        }
        catch (Exception ex)
        {
            var reason = ex.Message.Split('\n', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()?.Trim();
            ErrorMessage = string.IsNullOrWhiteSpace(reason)
                ? "Failed to load source catalog."
                : $"Failed to load source catalog: {reason}";
        }
    }
}

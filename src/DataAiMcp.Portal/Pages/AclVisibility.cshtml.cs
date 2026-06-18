using System.Security.Claims;
using DataAiMcp.Portal.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace DataAiMcp.Portal.Pages;

public class AclVisibilityModel : PageModel
{
    private readonly IMcpToolService _mcpToolService;

    public AclVisibilityModel(IMcpToolService mcpToolService)
    {
        _mcpToolService = mcpToolService;
    }

    [BindProperty]
    public string Query { get; set; } = "latest safety bulletin";

    [BindProperty]
    public int Top { get; set; } = 5;

    public string ResultPayload { get; private set; } = string.Empty;

    public string ResultMessage { get; private set; } = string.Empty;

    public bool IsSuccess { get; private set; }

    public string UserName => User.Identity?.Name ?? "(unknown)";

    public string ObjectId => User.FindFirstValue("http://schemas.microsoft.com/identity/claims/objectidentifier") ?? "(missing)";

    public string TenantId => User.FindFirstValue("http://schemas.microsoft.com/identity/claims/tenantid") ?? "(missing)";

    public int GroupOrRoleClaimCount =>
        User.Claims.Count(c => c.Type == "groups" || c.Type == "roles");

    public void OnGet()
    {
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        try
        {
            var args = new Dictionary<string, object?>
            {
                ["query"] = string.IsNullOrWhiteSpace(Query) ? "status" : Query,
                ["top"] = Top,
            };

            ResultPayload = await _mcpToolService
                .ExecuteToolAsync("search_documents", args, cancellationToken)
                .ConfigureAwait(false);

            IsSuccess = true;
            ResultMessage = "Visibility probe completed. Results shown are already ACL-filtered by MCP.";
        }
        catch (Exception ex)
        {
            IsSuccess = false;
            ResultMessage = $"Probe failed: {ex.Message}";
        }

        return Page();
    }
}

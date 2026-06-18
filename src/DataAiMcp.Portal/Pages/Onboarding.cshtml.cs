using DataAiMcp.Portal.Models;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.Extensions.Options;

namespace DataAiMcp.Portal.Pages;

public class OnboardingModel : PageModel
{
    private readonly PortalOptions _options;

    public OnboardingModel(IOptions<PortalOptions> options)
    {
        _options = options.Value;
    }

    public string McpAudience => _options.McpAudience;

    public string TenantHint => "Use Auth__TenantId from MCP app settings.";

    public void OnGet()
    {
    }
}

using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace DataAiMcp.McpServer.Auth;

/// <summary>
/// Resolves the per-request set of security identifiers used for document-level ACL trimming.
/// Pulls the caller's <c>oid</c> claim and the <c>groups</c> claim from the validated JWT, plus
/// pseudo-IDs that match documents tagged for the entire organization.
/// </summary>
/// <remarks>
/// When the request is anonymous (e.g. <c>Auth:RequireAuthenticatedUser=false</c> in dev), this
/// returns an empty collection - the orchestrator interprets that as "no ACL filter" so dev callers
/// see everything. In production the JwtBearer middleware enforces auth, so the empty path never runs.
/// </remarks>
public sealed class CallerSecurityContext
{
    private readonly IHttpContextAccessor _accessor;
    private readonly ILogger<CallerSecurityContext> _logger;

    public CallerSecurityContext(IHttpContextAccessor accessor, ILogger<CallerSecurityContext> logger)
    {
        _accessor = accessor;
        _logger = logger;
    }

    /// <summary>
    /// All security IDs to match against the <c>securityIds</c> field on indexed documents.
    /// Order is not significant; the orchestrator uses <c>search.in</c>.
    /// </summary>
    public IReadOnlyCollection<string> SecurityIds
    {
        get
        {
            var user = _accessor.HttpContext?.User;
            if (user?.Identity?.IsAuthenticated != true) return Array.Empty<string>();

            var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            // 1) Caller's object ID (Entra ID user/SP).
            var oid = user.FindFirst("oid")?.Value
                      ?? user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (!string.IsNullOrEmpty(oid)) ids.Add(oid);

            // 2) Group object IDs (when 'groups' is present and not in overage).
            foreach (var c in user.FindAll("groups"))
            {
                if (!string.IsNullOrEmpty(c.Value)) ids.Add(c.Value);
            }

            // 3) Roles (app roles assigned to the caller principal).
            foreach (var c in user.FindAll(ClaimTypes.Role))
            {
                if (!string.IsNullOrEmpty(c.Value)) ids.Add($"role:{c.Value}");
            }

            // 4) Pseudo-ID: every authenticated tenant member matches "__org__".
            ids.Add("__org__");

            // 5) Detect groups overage. When the token is too large to embed groups,
            // Entra emits "_claim_names" / "hasgroups" - the caller would need a Graph
            // round-trip (getMemberObjects) to enumerate. We log this so operators know
            // a group lookup pipeline is needed for that user.
            if (user.HasClaim(c => c.Type == "hasgroups" && c.Value == "true")
                || user.HasClaim(c => c.Type == "_claim_names"))
            {
                _logger.LogWarning(
                    "Caller {Oid} has groups overage - groups claim is truncated. ACL trimming may under-match. Consider Graph getMemberObjects fallback.",
                    oid ?? "<unknown>");
            }

            return ids;
        }
    }
}

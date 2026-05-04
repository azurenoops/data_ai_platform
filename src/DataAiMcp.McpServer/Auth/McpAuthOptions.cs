namespace DataAiMcp.McpServer.Auth;

public sealed class McpAuthOptions
{
    public const string SectionName = "Auth";

    public string TenantId { get; set; } = "";
    public string Audience { get; set; } = "";
    public bool RequireAuthenticatedUser { get; set; } = true;
}

public static class McpPolicies
{
    public const string ReadDocuments = "mcp.read_documents";
    public const string QueryStructured = "mcp.query_structured";
    public const string AdminTools = "mcp.admin";
}

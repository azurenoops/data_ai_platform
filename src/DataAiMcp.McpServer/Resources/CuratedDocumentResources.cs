namespace DataAiMcp.McpServer.Resources;

/// <summary>
/// Placeholder for surfacing curated documents (e.g. chunks/*) as MCP resources.
/// Once the resource binding contract is finalized, replace with WithResources&lt;T&gt; registration
/// using the appropriate URI templates and stream readers.
/// </summary>
public sealed class CuratedDocumentResources
{
    public string GetCuratedDocument(string path)
    {
        return $"Curated document handle for {path}.";
    }
}

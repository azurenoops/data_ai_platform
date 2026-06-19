using System.Text.Json;
using Azure.Core;
using Azure.Identity;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;

// Sample MCP client that:
// 1. Acquires an Entra access token for the configured audience.
// 2. Connects to the deployed MCP server via streamable HTTP at /mcp.
// 3. Lists tools and invokes search_documents and list_sources.
//
// Usage: dotnet run --project src/Samples/DataAiMcp.SampleClient.Console -- <baseUrl> <audience>

if (args.Length < 2)
{
    Console.Error.WriteLine("Usage: SampleClient <baseUrl> <audience>");
    Environment.Exit(2);
}

var baseUrl = args[0].TrimEnd('/');
var audience = args[1];

var credential = new DefaultAzureCredential();
var token = await credential.GetTokenAsync(new TokenRequestContext([$"{audience}/.default"]), CancellationToken.None);

using var httpClient = new HttpClient { BaseAddress = new Uri(baseUrl) };
httpClient.DefaultRequestHeaders.Authorization = new("Bearer", token.Token);

var transport = new SseClientTransport(new SseClientTransportOptions
{
    Endpoint = new Uri($"{baseUrl}/mcp"),
    Name = "data-ai-mcp",
    // AdditionalHeaders is nullable; assign a new dictionary instead of using a nested
    // collection initializer (CS8670 in newer ModelContextProtocol previews).
    AdditionalHeaders = new Dictionary<string, string>
    {
        ["Authorization"] = $"Bearer {token.Token}",
    },
});

await using var client = await McpClientFactory.CreateAsync(transport);

Console.WriteLine($"Connected to {baseUrl}/mcp - server={client.ServerInfo.Name} v{client.ServerInfo.Version}");

var tools = await client.ListToolsAsync();
Console.WriteLine($"Tools ({tools.Count}):");
foreach (var t in tools)
{
    Console.WriteLine($"  - {t.Name}: {t.Description}");
}

Console.WriteLine();
Console.WriteLine("Calling list_sources...");
var sources = await client.CallToolAsync("list_sources", new Dictionary<string, object?>());
PrintResult(sources);

Console.WriteLine();
Console.WriteLine("Calling search_documents(query='hello world', top=3)...");
var hits = await client.CallToolAsync("search_documents", new Dictionary<string, object?>
{
    ["query"] = "hello world",
    ["top"] = 3,
});
PrintResult(hits);

Console.WriteLine();
Console.WriteLine("Calling search_documents(query='projects over budget by sector', source='sql-demo', top=2)...");
var sqlDemoHits = await client.CallToolAsync("search_documents", new Dictionary<string, object?>
{
    ["query"] = "projects over budget by sector and region",
    ["source"] = "sql-demo",
    ["top"] = 2,
});
PrintResult(sqlDemoHits);

Console.WriteLine();
Console.WriteLine("Calling describe_dataset(name='projects')...");
var described = await client.CallToolAsync("describe_dataset", new Dictionary<string, object?>
{
    ["name"] = "projects",
});
PrintResult(described);

Console.WriteLine();
Console.WriteLine("Calling query_structured_data(question='Which projects are over budget? Return ProjectName, BudgetUsd, SpentUsd. Top 5.')...");
var structured = await client.CallToolAsync("query_structured_data", new Dictionary<string, object?>
{
    ["question"] = "Which projects are over budget (SpentUsd greater than BudgetUsd)? Return ProjectName, BudgetUsd, SpentUsd ordered by SpentUsd descending. Top 5.",
    ["dataset"] = "projects",
});
PrintResult(structured);

static void PrintResult(CallToolResult result)
{
    foreach (var content in result.Content)
    {
        if (content is TextContentBlock text)
        {
            Console.WriteLine(text.Text);
        }
        else
        {
            Console.WriteLine(JsonSerializer.Serialize(content));
        }
    }
}

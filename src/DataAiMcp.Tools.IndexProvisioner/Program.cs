using DataAiMcp.Shared.DependencyInjection;
using DataAiMcp.Shared.Search;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = Host.CreateApplicationBuilder(args);
builder.Configuration.AddEnvironmentVariables();

builder.Services.AddDataAiShared(builder.Configuration);

using var host = builder.Build();
var provisioner = host.Services.GetRequiredService<SearchIndexProvisioner>();

using var cts = new CancellationTokenSource(TimeSpan.FromMinutes(5));
await provisioner.EnsureIndexAsync(cts.Token);
Console.WriteLine("AI Search index provisioned successfully.");

using DataAiMcp.Shared.Storage;
using Microsoft.Extensions.Logging;
using Microsoft.Graph;

namespace DataAiMcp.Ingestion.Functions.Graph;

/// <summary>
/// Drains a SharePoint document library or OneDrive drive via Microsoft Graph and lands
/// each binary into the ADLS Gen2 <c>landing</c> container. The blob path encodes the
/// originating drive + item ID so the blob-trigger pipeline can reconstruct provenance.
/// </summary>
public sealed class GraphFileFetcher
{
    private readonly GraphClientFactory _graph;
    private readonly IDataLakeRepository _lake;
    private readonly ILogger<GraphFileFetcher> _logger;

    public GraphFileFetcher(GraphClientFactory graph, IDataLakeRepository lake, ILogger<GraphFileFetcher> logger)
    {
        _graph = graph;
        _lake = lake;
        _logger = logger;
    }

    public async Task<int> SyncDriveAsync(
        string driveId,
        string source,
        string landingPathPrefix,
        CancellationToken cancellationToken)
    {
        var graph = _graph.Client;
        var processed = 0;

        // breadth-first traversal from drive root
        var stack = new Stack<string>();
        stack.Push("root");

        while (stack.Count > 0 && !cancellationToken.IsCancellationRequested)
        {
            var itemId = stack.Pop();
            var children = await graph.Drives[driveId].Items[itemId].Children.GetAsync(cancellationToken: cancellationToken).ConfigureAwait(false);
            foreach (var child in children?.Value ?? [])
            {
                if (child.Folder is not null && child.Id is not null)
                {
                    stack.Push(child.Id);
                    continue;
                }
                if (child.File is null || child.Id is null) continue;

                var blobPath = $"{landingPathPrefix.TrimEnd('/')}/{driveId}/{child.Id}-{Sanitize(child.Name)}";
                if (await _lake.ExistsAsync(StorageContainer.Landing, blobPath, cancellationToken).ConfigureAwait(false))
                {
                    continue;
                }

                await using var content = await graph.Drives[driveId].Items[child.Id].Content.GetAsync(cancellationToken: cancellationToken).ConfigureAwait(false);
                if (content is null) continue;

                var securityIds = await ResolveSecurityIdsAsync(driveId, child.Id, cancellationToken).ConfigureAwait(false);

                var metadata = new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    ["source"] = source,
                    ["graphDriveId"] = driveId,
                    ["graphItemId"] = child.Id,
                    ["originalName"] = child.Name ?? "",
                    ["webUrl"] = child.WebUrl ?? "",
                    ["securityIds"] = string.Join(",", securityIds),
                };

                await _lake.UploadAsync(
                    StorageContainer.Landing,
                    blobPath,
                    content,
                    contentType: child.File.MimeType,
                    metadata: metadata,
                    cancellationToken: cancellationToken).ConfigureAwait(false);

                processed++;
                _logger.LogInformation("Landed Graph file {Source}/{Path} ({Bytes} bytes).", source, blobPath, child.Size ?? 0);
            }
        }

        return processed;
    }

    private static string Sanitize(string? name)
    {
        if (string.IsNullOrEmpty(name)) return "file";
        var invalid = Path.GetInvalidFileNameChars();
        return new string(name.Select(c => invalid.Contains(c) ? '_' : c).ToArray());
    }

    /// <summary>
    /// Pulls Graph permissions for a drive item and projects them onto a flat list of
    /// security identifiers that the Search filter can match against the caller's claims.
    /// Pseudo-identifiers <c>__org__</c> (organization-wide) and <c>__everyone__</c> (anonymous)
    /// are emitted for the corresponding link types.
    /// </summary>
    private async Task<HashSet<string>> ResolveSecurityIdsAsync(string driveId, string itemId, CancellationToken cancellationToken)
    {
        var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            var perms = await _graph.Client.Drives[driveId].Items[itemId].Permissions
                .GetAsync(cancellationToken: cancellationToken)
                .ConfigureAwait(false);

            foreach (var p in perms?.Value ?? [])
            {
                // Direct grants (single identity).
                AddIfPresent(ids, p.GrantedToV2?.User?.Id);
                AddIfPresent(ids, p.GrantedToV2?.Group?.Id);
                AddIfPresent(ids, p.GrantedToV2?.SiteUser?.Id);
                AddIfPresent(ids, p.GrantedToV2?.SiteGroup?.Id);

                // Sharing-link grants (collection of identities).
                foreach (var ident in p.GrantedToIdentitiesV2 ?? [])
                {
                    AddIfPresent(ids, ident.User?.Id);
                    AddIfPresent(ids, ident.Group?.Id);
                    AddIfPresent(ids, ident.SiteUser?.Id);
                    AddIfPresent(ids, ident.SiteGroup?.Id);
                }

                // Sharing-link scopes -> pseudo-IDs.
                var scope = p.Link?.Scope?.ToLowerInvariant();
                if (scope == "anonymous") ids.Add("__everyone__");
                if (scope == "organization") ids.Add("__org__");
                if (scope == "users")
                {
                    // 'users' scope: identities are in GrantedToIdentitiesV2 already, no pseudo-ID needed.
                }
            }
        }
        catch (Exception ex)
        {
            // Permissions read can fail (e.g. throttling). Falling open here would defeat ACL trimming,
            // so we fail closed: the document gets no securityIds and is only visible to indexer/admins.
            _logger.LogWarning(ex, "Failed to read Graph permissions for drive {Drive} item {Item}; falling closed.", driveId, itemId);
        }
        return ids;
    }

    private static void AddIfPresent(HashSet<string> set, string? id)
    {
        if (!string.IsNullOrEmpty(id)) set.Add(id);
    }
}

namespace DataAiMcp.Shared.Ingestion;

/// <summary>
/// Represents a data source configuration stored in CosmosDB or Table Storage.
/// Operators configure sources via the Portal; the dispatcher function reads these
/// and invokes the appropriate fetcher at runtime.
/// </summary>
public record SourceConfiguration
{
    /// <summary>Unique identifier: "{sourceType}-{guid}" (e.g., "teams-a1b2c3d4").</summary>
    public string Id { get; init; } = string.Empty;

    /// <summary>Source type: "teams", "onedrive", "sharepoint", "aws-s3", "google-drive", etc.</summary>
    public string SourceType { get; init; } = string.Empty;

    /// <summary>
    /// Source-specific settings as a flat key-value dictionary.
    /// Examples:
    ///   teams: { "teamId": "...", "channelId": "..." }
    ///   onedrive: { "driveIds": "drive1,drive2" }
    ///   aws-s3: { "bucketName": "...", "roleArn": "..." }
    /// </summary>
    public Dictionary<string, string> Settings { get; init; } = new();

    /// <summary>Cron schedule for this source (6-field format). Default: every 6 hours.</summary>
    public string Schedule { get; init; } = "0 0 */6 * * *";

    /// <summary>Whether this source is currently enabled.</summary>
    public bool Enabled { get; init; } = true;

    /// <summary>UTC timestamp when the source was added.</summary>
    public DateTime CreatedAt { get; init; }

    /// <summary>AAD object ID of the portal operator who added this source.</summary>
    public string CreatedBy { get; init; } = string.Empty;

    /// <summary>UTC timestamp of last modification.</summary>
    public DateTime? ModifiedAt { get; init; }

    /// <summary>AAD object ID of the operator who last modified this source.</summary>
    public string? ModifiedBy { get; init; }

    /// <summary>Optional: friendly display name.</summary>
    public string? DisplayName { get; init; }

    /// <summary>Optional: ingestion status notes (e.g., "Last run: 2026-06-17 14:23:45Z, 42 files").</summary>
    public string? LastRunStatus { get; init; }

    /// <summary>Optional: UTC timestamp of last successful ingestion.</summary>
    public DateTime? LastRunAt { get; init; }

    /// <summary>CosmosDB partition key.</summary>
    [System.Text.Json.Serialization.JsonPropertyName("partitionKey")]
    public string PartitionKey => SourceType;
}

using DataAiMcp.Shared.Ingestion;
using Microsoft.Extensions.Logging;

namespace DataAiMcp.Portal.Services;

/// <summary>
/// Implementation of source configuration service for the Portal.
/// </summary>
public sealed class SourceConfigurationService : ISourceConfigurationService
{
    private readonly ISourceConfigurationStore _store;
    private readonly ISourceFetcherFactory _fetcherFactory;
    private readonly ILogger<SourceConfigurationService> _logger;

    public SourceConfigurationService(
        ISourceConfigurationStore store,
        ISourceFetcherFactory fetcherFactory,
        ILogger<SourceConfigurationService> logger)
    {
        _store = store;
        _fetcherFactory = fetcherFactory;
        _logger = logger;
    }

    public async Task<IEnumerable<SourceConfiguration>> GetAllSourcesAsync(CancellationToken cancellationToken)
    {
        return await _store.GetAllSourcesAsync(cancellationToken);
    }

    public async Task<IEnumerable<SourceConfiguration>> GetEnabledSourcesAsync(CancellationToken cancellationToken)
    {
        return await _store.GetEnabledSourcesAsync(cancellationToken);
    }

    public async Task<SourceConfiguration?> GetSourceByIdAsync(string id, CancellationToken cancellationToken)
    {
        return await _store.GetSourceByIdAsync(id, cancellationToken);
    }

    public async Task<(bool IsValid, SourceConfiguration? Source, List<string> Errors)> ValidateAndCreateAsync(
        string sourceType,
        Dictionary<string, string> settings,
        string? displayName,
        string userOid,
        CancellationToken cancellationToken)
    {
        var errors = new List<string>();

        // Validate source type is supported
        var supportedTypes = GetSupportedSourceTypes();
        var typeInfo = supportedTypes.FirstOrDefault(t => t.SourceType == sourceType);
        if (typeInfo is null || !typeInfo.Implemented)
        {
            errors.Add($"Source type '{sourceType}' is not supported");
            return (false, null, errors);
        }

        // Validate required settings
        foreach (var requiredSetting in typeInfo.RequiredSettings)
        {
            if (!settings.TryGetValue(requiredSetting.Key, out var value) || string.IsNullOrWhiteSpace(value))
            {
                errors.Add($"Missing required setting: {requiredSetting.Label}");
            }
        }

        if (errors.Count > 0)
            return (false, null, errors);

        // Validate settings with fetcher
        try
        {
            var fetcher = _fetcherFactory.CreateFetcher(sourceType);
            if (!await fetcher.ValidateAsync(settings, cancellationToken))
            {
                errors.Add($"Source validation failed: unable to access {sourceType} with provided settings");
                return (false, null, errors);
            }
        }
        catch (NotSupportedException)
        {
            errors.Add($"Fetcher for source type '{sourceType}' is not available");
            return (false, null, errors);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Validation failed for source type {SourceType}", sourceType);
            errors.Add($"Validation error: {ex.Message}");
            return (false, null, errors);
        }

        // Create the source configuration
        var sourceId = $"{sourceType}-{Guid.NewGuid().ToString("N")[..8]}";
        var source = new SourceConfiguration
        {
            Id = sourceId,
            SourceType = sourceType,
            Settings = new Dictionary<string, string>(settings),
            DisplayName = displayName ?? $"{typeInfo.DisplayName} ({sourceId})",
            Enabled = true,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = userOid,
        };

        await _store.SaveAsync(source, cancellationToken);
        _logger.LogInformation("Created source configuration {SourceId} ({SourceType}) for user {UserId}",
            sourceId, sourceType, userOid);

        return (true, source, new());
    }

    public async Task ToggleSourceAsync(string id, bool enabled, CancellationToken cancellationToken)
    {
        await _store.ToggleEnabledAsync(id, enabled, cancellationToken);
        _logger.LogInformation("Toggled source {SourceId} to {Enabled}", id, enabled);
    }

    public async Task DeleteSourceAsync(string id, CancellationToken cancellationToken)
    {
        await _store.DeleteAsync(id, cancellationToken);
        _logger.LogInformation("Deleted source {SourceId}", id);
    }

    public IReadOnlyList<SourceTypeInfo> GetSupportedSourceTypes()
    {
        return new List<SourceTypeInfo>
        {
            new()
            {
                SourceType = "onedrive",
                DisplayName = "OneDrive",
                Description = "Microsoft OneDrive personal and business drives",
                Implemented = false, // TODO: refactor GraphFileFetcher to support streaming
                RequiredSettings = new()
                {
                    new()
                    {
                        Key = "driveIds",
                        Label = "Drive IDs",
                        Description = "Comma-separated list of OneDrive drive IDs (e.g., 'b!abc123,b!def456')",
                        Type = "text",
                        Required = true,
                    }
                }
            },
            new()
            {
                SourceType = "sharepoint",
                DisplayName = "SharePoint",
                Description = "Microsoft SharePoint document libraries",
                Implemented = false, // TODO: refactor GraphFileFetcher to support streaming
                RequiredSettings = new()
                {
                    new()
                    {
                        Key = "driveIds",
                        Label = "Drive IDs",
                        Description = "Comma-separated list of SharePoint drive IDs",
                        Type = "text",
                        Required = true,
                    }
                }
            },
            new()
            {
                SourceType = "teams",
                DisplayName = "Microsoft Teams",
                Description = "Files from Teams channels",
                Implemented = false, // TODO: implement TeamsSourceFetcher
                RequiredSettings = new()
                {
                    new()
                    {
                        Key = "teamId",
                        Label = "Team ID",
                        Description = "The Teams group ID",
                        Type = "text",
                        Required = true,
                    },
                    new()
                    {
                        Key = "channelIds",
                        Label = "Channel IDs (optional)",
                        Description = "Comma-separated list of channel IDs (leave blank for all channels)",
                        Type = "text",
                        Required = false,
                    }
                }
            },
            new()
            {
                SourceType = "aws-s3",
                DisplayName = "AWS S3",
                Description = "Amazon S3 buckets",
                Implemented = false, // TODO: implement AwsS3SourceFetcher
                RequiredSettings = new()
                {
                    new()
                    {
                        Key = "bucketName",
                        Label = "Bucket Name",
                        Description = "AWS S3 bucket name",
                        Type = "text",
                        Required = true,
                    },
                    new()
                    {
                        Key = "prefix",
                        Label = "Key Prefix (optional)",
                        Description = "S3 key prefix to filter objects",
                        Type = "text",
                        Required = false,
                    }
                }
            },
            new()
            {
                SourceType = "google-drive",
                DisplayName = "Google Drive",
                Description = "Google Drive and Google Workspace files",
                Implemented = false, // TODO: implement GoogleDriveSourceFetcher
                RequiredSettings = new()
                {
                    new()
                    {
                        Key = "folderId",
                        Label = "Folder ID",
                        Description = "Google Drive folder ID",
                        Type = "text",
                        Required = true,
                    },
                    new()
                    {
                        Key = "serviceAccountEmail",
                        Label = "Service Account Email",
                        Description = "Google service account email (must have access to the folder)",
                        Type = "text",
                        Required = true,
                    }
                }
            },
            new()
            {
                SourceType = "afs",
                DisplayName = "Azure File Share",
                Description = "Files from Azure Storage file shares",
                Implemented = false, // TODO: implement AfsSourceFetcher
                RequiredSettings = new()
                {
                    new()
                    {
                        Key = "shareName",
                        Label = "Share Name",
                        Description = "Azure file share name",
                        Type = "text",
                        Required = true,
                    }
                }
            },
        }.AsReadOnly();
    }
}

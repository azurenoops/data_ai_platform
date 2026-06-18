using DataAiMcp.Shared.Ingestion;

namespace DataAiMcp.Portal.Services;

/// <summary>
/// Service for the Portal to manage source configurations.
/// Provides UI-friendly operations for listing, validating, and managing sources.
/// </summary>
public interface ISourceConfigurationService
{
    /// <summary>Gets all source configurations for display in the Portal.</summary>
    Task<IEnumerable<SourceConfiguration>> GetAllSourcesAsync(CancellationToken cancellationToken);

    /// <summary>Gets all enabled sources.</summary>
    Task<IEnumerable<SourceConfiguration>> GetEnabledSourcesAsync(CancellationToken cancellationToken);

    /// <summary>Gets a specific source by ID.</summary>
    Task<SourceConfiguration?> GetSourceByIdAsync(string id, CancellationToken cancellationToken);

    /// <summary>
    /// Validates and creates a new source configuration.
    /// Returns validation errors if invalid.
    /// </summary>
    Task<(bool IsValid, SourceConfiguration? Source, List<string> Errors)> ValidateAndCreateAsync(
        string sourceType,
        Dictionary<string, string> settings,
        string? displayName,
        string userOid,
        CancellationToken cancellationToken);

    /// <summary>Toggles a source's enabled state.</summary>
    Task ToggleSourceAsync(string id, bool enabled, CancellationToken cancellationToken);

    /// <summary>Deletes a source configuration.</summary>
    Task DeleteSourceAsync(string id, CancellationToken cancellationToken);

    /// <summary>Gets metadata about supported source types.</summary>
    IReadOnlyList<SourceTypeInfo> GetSupportedSourceTypes();
}

/// <summary>Metadata about a supported source type.</summary>
public record SourceTypeInfo
{
    public string SourceType { get; init; } = string.Empty;
    public string DisplayName { get; init; } = string.Empty;
    public string Description { get; init; } = string.Empty;
    public bool Implemented { get; init; }
    public List<SourceSettingInfo> RequiredSettings { get; init; } = new();
    public List<SourceSettingInfo> OptionalSettings { get; init; } = new();
}

/// <summary>Metadata about a setting for a source type.</summary>
public record SourceSettingInfo
{
    public string Key { get; init; } = string.Empty;
    public string Label { get; init; } = string.Empty;
    public string Description { get; init; } = string.Empty;
    public string Type { get; init; } = "text"; // text, password, number, checkbox, select
    public bool Required { get; init; } = true;
    public List<string>? SelectOptions { get; init; }
    public string? Placeholder { get; init; }
}

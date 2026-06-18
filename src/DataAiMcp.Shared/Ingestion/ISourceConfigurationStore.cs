namespace DataAiMcp.Shared.Ingestion;

/// <summary>
/// Repository for managing source configurations. Implementations persist
/// to CosmosDB or Table Storage.
/// </summary>
public interface ISourceConfigurationStore
{
    /// <summary>Gets all enabled source configurations.</summary>
    Task<IEnumerable<SourceConfiguration>> GetEnabledSourcesAsync(CancellationToken cancellationToken);

    /// <summary>Gets all source configurations (enabled or disabled).</summary>
    Task<IEnumerable<SourceConfiguration>> GetAllSourcesAsync(CancellationToken cancellationToken);

    /// <summary>Gets a specific source configuration by ID.</summary>
    Task<SourceConfiguration?> GetSourceByIdAsync(string id, CancellationToken cancellationToken);

    /// <summary>Gets all sources of a specific type.</summary>
    Task<IEnumerable<SourceConfiguration>> GetSourcesByTypeAsync(string sourceType, CancellationToken cancellationToken);

    /// <summary>Saves a new or updated source configuration.</summary>
    Task SaveAsync(SourceConfiguration source, CancellationToken cancellationToken);

    /// <summary>Deletes a source configuration by ID.</summary>
    Task DeleteAsync(string id, CancellationToken cancellationToken);

    /// <summary>Toggles the enabled state of a source.</summary>
    Task ToggleEnabledAsync(string id, bool enabled, CancellationToken cancellationToken);

    /// <summary>Updates the last run status of a source.</summary>
    Task UpdateLastRunAsync(
        string id,
        int itemCount,
        bool success,
        string? errorMessage,
        CancellationToken cancellationToken);
}

using System.ComponentModel.DataAnnotations;

namespace DataAiMcp.Portal.Models;

public sealed class PortalOptions
{
    [Required]
    public string McpBaseUrl { get; set; } = string.Empty;

    [Required]
    public string McpAudience { get; set; } = string.Empty;

    [Required]
    public string SubscriptionId { get; set; } = string.Empty;

    [Required]
    public string ResourceGroupName { get; set; } = string.Empty;

    [Required]
    public string DataFactoryName { get; set; } = string.Empty;

    [Required]
    public string SqlPipelineName { get; set; } = string.Empty;

    [Required]
    public string StorageAccountUrl { get; set; } = string.Empty;

    [Required]
    public string LandingContainerName { get; set; } = string.Empty;
}

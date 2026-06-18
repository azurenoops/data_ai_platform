namespace DataAiMcp.Portal.Models;

public sealed class CopyActivitySummary
{
    public string ActivityName { get; set; } = string.Empty;

    public string Status { get; set; } = string.Empty;

    public long RowsCopied { get; set; }

    public long FilesWritten { get; set; }

    public long DataRead { get; set; }

    public string ErrorCode { get; set; } = string.Empty;
}

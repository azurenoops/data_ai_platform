using System.ComponentModel.DataAnnotations;
using DataAiMcp.Portal.Models;
using DataAiMcp.Portal.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.Extensions.Options;

namespace DataAiMcp.Portal.Pages;

public class UploadModel : PageModel
{
    private readonly IStorageLandingService _storageLandingService;
    private readonly PortalOptions _options;

    public UploadModel(IStorageLandingService storageLandingService, IOptions<PortalOptions> options)
    {
        _storageLandingService = storageLandingService;
        _options = options.Value;
    }

    [BindProperty]
    [Display(Name = "Folder")]
    public string Folder { get; set; } = "demo/manual-drop";

    [BindProperty]
    [Required]
    [Display(Name = "File")]
    public IFormFile? UploadFile { get; set; }

    public string ResultMessage { get; private set; } = string.Empty;

    public bool IsSuccess { get; private set; }

    public string StorageAccountUrl => _options.StorageAccountUrl;

    public string LandingContainerName => _options.LandingContainerName;

    public void OnGet()
    {
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        if (!ModelState.IsValid || UploadFile is null || UploadFile.Length <= 0)
        {
            IsSuccess = false;
            ResultMessage = "Select a non-empty file before uploading.";
            return Page();
        }

        await using var stream = UploadFile.OpenReadStream();
        try
        {
            var uploadedPath = await _storageLandingService
                .UploadAsync(UploadFile.FileName, Folder, stream, cancellationToken)
                .ConfigureAwait(false);

            IsSuccess = true;
            ResultMessage = $"Uploaded successfully to {uploadedPath}.";
        }
        catch (Exception ex)
        {
            IsSuccess = false;
            ResultMessage = $"Upload failed: {ex.Message}";
        }

        return Page();
    }
}

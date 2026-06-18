using System.Text.Json;
using Azure.Messaging;
using DataAiMcp.Ingestion.Functions.Pipeline;
using DataAiMcp.Shared.Storage;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace DataAiMcp.Ingestion.Functions;

/// <summary>
/// HTTP-triggered wrapper for Event Grid ingestion. Event Grid delivers events via HTTP POST;
/// this function accepts them and processes blobs through the document ingestion pipeline.
/// </summary>
public sealed class IngestBlobHttpFunction
{
    private readonly DocumentIngestionPipeline _pipeline;
    private readonly IDataLakeRepository _lake;
    private readonly ILogger<IngestBlobHttpFunction> _logger;

    public IngestBlobHttpFunction(DocumentIngestionPipeline pipeline, IDataLakeRepository lake, ILogger<IngestBlobHttpFunction> logger)
    {
        _pipeline = pipeline;
        _lake = lake;
        _logger = logger;
    }

    [Function("IngestBlobHttp")]
    public async Task<HttpResponseData> RunAsync(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "IngestBlobHttp")] HttpRequestData req,
        CancellationToken cancellationToken)
    {
        try
        {
            var failures = new List<string>();

            // Event Grid sends validation requests to the subscription endpoint
            if (req.Headers.Contains("aeg-event-type") &&
                req.Headers.GetValues("aeg-event-type").First() == "SubscriptionValidation")
            {
                _logger.LogInformation("Event Grid subscription validation request received.");

                using var reader = new StreamReader(req.Body);
                var content = await reader.ReadToEndAsync(cancellationToken).ConfigureAwait(false);
                var jsonElement = JsonSerializer.Deserialize<JsonElement>(content);

                if (jsonElement.ValueKind == JsonValueKind.Array &&
                    jsonElement.GetArrayLength() > 0 &&
                    jsonElement[0].TryGetProperty("data", out var dataElement) &&
                    dataElement.TryGetProperty("validationCode", out var codeElement))
                {
                    var validationCode = codeElement.GetString();
                    var response = req.CreateResponse();
                    response.StatusCode = System.Net.HttpStatusCode.OK;

                    var responseData = new { validationResponse = validationCode };
                    await response.WriteAsJsonAsync(responseData, cancellationToken).ConfigureAwait(false);
                    return response;
                }

                _logger.LogWarning("Event Grid subscription validation payload did not contain a validationCode.");
            }

            // Parse Event Grid events from request body
            using var bodyReader = new StreamReader(req.Body);
            var bodyContent = await bodyReader.ReadToEndAsync(cancellationToken).ConfigureAwait(false);
            
            _logger.LogInformation("Event Grid HTTP request body: {Body}", bodyContent);

            var events = JsonSerializer.Deserialize<JsonElement[]>(bodyContent);
            if (events == null || events.Length == 0)
            {
                _logger.LogWarning("No events in request body.");
                var badResponse = req.CreateResponse();
                badResponse.StatusCode = System.Net.HttpStatusCode.BadRequest;
                return badResponse;
            }

            // Process each event
            foreach (var eventElement in events)
            {
                try
                {
                    // Event Grid events can be in CloudEvent or EventGridEvent format
                    // Try CloudEvent format first
                    if (eventElement.TryGetProperty("data", out var dataElement) &&
                        dataElement.TryGetProperty("url", out var urlElement))
                    {
                        var blobUrl = urlElement.GetString();
                        if (string.IsNullOrEmpty(blobUrl))
                        {
                            _logger.LogWarning("Event Grid message has empty 'url'.");
                            continue;
                        }

                        // Extract blob name from URL
                        var uri = new Uri(blobUrl);
                        var path = uri.AbsolutePath.TrimStart('/');
                        var segments = path.Split('/', 2);
                        
                        if (segments.Length < 2 || segments[0] != "landing")
                        {
                            _logger.LogWarning("Invalid blob path {Path}; expected landing/file.", path);
                            continue;
                        }

                        var name = segments[1];
                        _logger.LogInformation("IngestBlobHttp triggered for {Blob}.", name);

                        // Download and process blob
                        using var blobContent = await _lake.OpenReadAsync(StorageContainer.Landing, name, cancellationToken).ConfigureAwait(false);
                        _logger.LogInformation("IngestBlobHttp ingesting {Blob}.", name);
                        await _pipeline.IngestAsync(name, blobContent, blobMetadata: null, cancellationToken).ConfigureAwait(false);
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error processing event.");
                    failures.Add(ex.ToString());
                }
            }

            if (failures.Count > 0)
            {
                var errorResponse = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                await errorResponse.WriteAsJsonAsync(new { errors = failures }, cancellationToken).ConfigureAwait(false);
                return errorResponse;
            }

            var okResponse = req.CreateResponse();
            okResponse.StatusCode = System.Net.HttpStatusCode.OK;
            return okResponse;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "IngestBlobHttp failed.");
            var errorResponse = req.CreateResponse();
            errorResponse.StatusCode = System.Net.HttpStatusCode.InternalServerError;
            return errorResponse;
        }
    }
}

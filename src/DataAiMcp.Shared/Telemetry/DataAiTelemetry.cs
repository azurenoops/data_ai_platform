using System.Diagnostics;
using System.Diagnostics.Metrics;

namespace DataAiMcp.Shared.Telemetry;

/// <summary>
/// Static singletons for cross-cutting telemetry. Use <see cref="ActivitySource"/> for traces and
/// <see cref="Meter"/> for metrics so consumers (Functions, App Service) can wire them via OpenTelemetry.
/// </summary>
public static class DataAiTelemetry
{
    public const string SourceName = "DataAiMcp";
    public const string MeterName = "DataAiMcp";

    public static readonly ActivitySource ActivitySource = new(SourceName);
    public static readonly Meter Meter = new(MeterName);

    public static readonly Counter<long> ChunksIndexed = Meter.CreateCounter<long>("dataai.chunks.indexed", unit: "{chunks}");
    public static readonly Histogram<double> EmbeddingLatencyMs = Meter.CreateHistogram<double>("dataai.embeddings.latency", unit: "ms");
    public static readonly Histogram<double> SearchLatencyMs = Meter.CreateHistogram<double>("dataai.search.latency", unit: "ms");
    /// <summary>Wall-clock latency of the per-document AI Search upsert. Powers the
    /// <c>search_ingestion_latency</c> alert in <c>infra/modules/monitoring/alerts.tf</c>.</summary>
    public static readonly Histogram<long> IndexLatencyMs = Meter.CreateHistogram<long>("ingestion.IndexLatencyMs", unit: "ms");
    public static readonly Counter<long> ToolInvocations = Meter.CreateCounter<long>("dataai.mcp.tool.invocations", unit: "{calls}");
}

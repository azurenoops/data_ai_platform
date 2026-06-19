USE datalake;
GO

CREATE OR ALTER VIEW dbo.vw_sqlmi_telemetryreadings AS
SELECT
    ReadingId   = TRY_CONVERT(int,            src.[ReadingId]),
    ProjectId   = TRY_CONVERT(int,            src.[ProjectId]),
    CapturedAt  = TRY_CONVERT(datetime2,      src.[CapturedAt]),
    MetricName  = TRY_CONVERT(nvarchar(80),   src.[MetricName]),
    MetricValue = TRY_CONVERT(decimal(12,3),  src.[MetricValue]),
    HealthState = TRY_CONVERT(nvarchar(20),   src.[HealthState])
FROM
    OPENROWSET(
        BULK 'https://__STORAGE_ACCOUNT__.dfs.core.windows.net/raw/sqlmi/TelemetryReadings/**',
        FORMAT = 'PARQUET'
    ) AS src;
GO

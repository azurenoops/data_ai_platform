USE datalake;
GO

CREATE OR ALTER VIEW dbo.vw_sqlmi_inspectionfindings AS
SELECT
    FindingId   = TRY_CONVERT(int,            src.[FindingId]),
    WorkOrderId = TRY_CONVERT(int,            src.[WorkOrderId]),
    FindingType = TRY_CONVERT(nvarchar(50),   src.[FindingType]),
    Result      = TRY_CONVERT(nvarchar(20),   src.[Result]),
    Notes       = TRY_CONVERT(nvarchar(500),  src.[Notes]),
    CapturedAt  = TRY_CONVERT(datetime2,      src.[CapturedAt])
FROM
    OPENROWSET(
        BULK 'https://__STORAGE_ACCOUNT__.dfs.core.windows.net/raw/sqlmi/InspectionFindings/**',
        FORMAT = 'PARQUET'
    ) AS src;
GO

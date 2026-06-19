USE datalake;
GO

CREATE OR ALTER VIEW dbo.vw_sqlmi_workorders AS
SELECT
    WorkOrderId = TRY_CONVERT(int,           src.[WorkOrderId]),
    ProjectId   = TRY_CONVERT(int,           src.[ProjectId]),
    Status      = TRY_CONVERT(nvarchar(40),  src.[Status]),
    Severity    = TRY_CONVERT(nvarchar(20),  src.[Severity]),
    SystemArea  = TRY_CONVERT(nvarchar(80),  src.[SystemArea]),
    HoursOpen   = TRY_CONVERT(int,           src.[HoursOpen]),
    OpenedDate  = TRY_CONVERT(date,          src.[OpenedDate])
FROM
    OPENROWSET(
        BULK 'https://__STORAGE_ACCOUNT__.dfs.core.windows.net/raw/sqlmi/WorkOrders/**',
        FORMAT = 'PARQUET'
    ) AS src;
GO

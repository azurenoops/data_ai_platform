USE datalake;
GO

CREATE OR ALTER VIEW dbo.vw_sqlmi_projects AS
SELECT
    ProjectId     = TRY_CONVERT(int,            src.[ProjectId]),
    CustomerId    = TRY_CONVERT(int,            src.[CustomerId]),
    ProjectName   = TRY_CONVERT(nvarchar(220),  src.[ProjectName]),
    Status        = TRY_CONVERT(nvarchar(40),   src.[Status]),
    BudgetUsd     = TRY_CONVERT(bigint,         src.[BudgetUsd]),
    SpentUsd      = TRY_CONVERT(bigint,         src.[SpentUsd]),
    StartDate     = TRY_CONVERT(date,           src.[StartDate]),
    TargetEndDate = TRY_CONVERT(date,           src.[TargetEndDate])
FROM
    OPENROWSET(
        BULK 'https://__STORAGE_ACCOUNT__.dfs.core.windows.net/raw/sqlmi/Projects/**',
        FORMAT = 'PARQUET'
    ) AS src;
GO

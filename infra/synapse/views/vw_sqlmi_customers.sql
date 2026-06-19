USE datalake;
GO

CREATE OR ALTER VIEW dbo.vw_sqlmi_customers AS
SELECT
    CustomerId    = TRY_CONVERT(int,            src.[CustomerId]),
    CustomerName  = TRY_CONVERT(nvarchar(200),  src.[CustomerName]),
    Sector        = TRY_CONVERT(nvarchar(80),   src.[Sector]),
    Region        = TRY_CONVERT(nvarchar(40),   src.[Region]),
    OnboardedDate = TRY_CONVERT(date,           src.[OnboardedDate])
FROM
    OPENROWSET(
        BULK 'https://__STORAGE_ACCOUNT__.dfs.core.windows.net/raw/sqlmi/Customers/**',
        FORMAT = 'PARQUET'
    ) AS src;
GO

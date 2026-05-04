USE datalake;
GO

CREATE OR ALTER VIEW dbo.vw_sqlmi_orders AS
SELECT
    orderid     = TRY_CONVERT(bigint,         src.[orderid]),
    customerid  = TRY_CONVERT(bigint,         src.[customerid]),
    orderdate   = TRY_CONVERT(date,           src.[orderdate]),
    totalamount = TRY_CONVERT(decimal(18,2),  src.[totalamount])
FROM
    OPENROWSET(
        BULK 'https://__STORAGE_ACCOUNT__.dfs.core.windows.net/curated/sqlmi/orders/**',
        FORMAT = 'PARQUET'
    ) AS src;
GO

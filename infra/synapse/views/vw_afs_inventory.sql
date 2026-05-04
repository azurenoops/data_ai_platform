USE datalake;
GO

CREATE OR ALTER VIEW dbo.vw_afs_inventory AS
SELECT
    [share]      = TRY_CONVERT(nvarchar(200),  src.[share]),
    filepath     = TRY_CONVERT(nvarchar(1024), src.[filepath]),
    sizebytes    = TRY_CONVERT(bigint,         src.[sizebytes]),
    snapshotdate = TRY_CONVERT(date,           src.[snapshotdate])
FROM
    OPENROWSET(
        BULK 'https://__STORAGE_ACCOUNT__.dfs.core.windows.net/curated/afs/inventory/**',
        FORMAT = 'PARQUET'
    ) AS src;
GO

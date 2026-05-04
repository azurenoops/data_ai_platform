-- Curated view over Dataverse Account table delivered via Azure Synapse Link for Dataverse.
-- Synapse Link writes Parquet (or CDM) into the configured ADLS Gen2 filesystem; this view
-- normalizes column casing and exposes only the fields we want surfaced to the MCP query tool.
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'datalake')
    CREATE DATABASE datalake;
GO

USE datalake;
GO

CREATE OR ALTER VIEW dbo.vw_dataverse_account AS
SELECT
    accountid       = TRY_CONVERT(uniqueidentifier, src.[accountid]),
    name            = TRY_CONVERT(nvarchar(160),    src.[name]),
    revenue         = TRY_CONVERT(decimal(18,2),    src.[revenue]),
    modifiedon      = TRY_CONVERT(datetime2,        src.[modifiedon])
FROM
    OPENROWSET(
        BULK 'https://__STORAGE_ACCOUNT__.dfs.core.windows.net/curated/dataverse/account/**',
        FORMAT = 'PARQUET'
    ) AS src;
GO

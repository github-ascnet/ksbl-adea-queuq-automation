SET NOCOUNT ON;

DECLARE @ResolvedBackfeedRunId uniqueidentifier = TRY_CONVERT(uniqueidentifier, @BackfeedRunId);

;WITH [CurrentRunSource] AS (
    SELECT
        s.[SourceSystem],
        s.[PermissionType],
        s.[MailboxKey],
        s.[TrusteeKey],
        ROW_NUMBER() OVER (
            PARTITION BY
                s.[SourceSystem],
                s.[PermissionType],
                s.[MailboxKey],
                s.[TrusteeKey]
            ORDER BY s.[Id] ASC
        ) AS [RowNumber]
    FROM [dbo].[stg_MailboxPermissions_Backfeed] AS s
    WHERE s.[BackfeedRunId] = @ResolvedBackfeedRunId
),
[SourceRows] AS (
    SELECT
        [SourceSystem],
        [PermissionType],
        [MailboxKey],
        [TrusteeKey]
    FROM [CurrentRunSource]
    WHERE [RowNumber] = 1
)
SELECT
    CAST((SELECT COUNT(1) FROM [SourceRows]) AS int) AS [CurrentRunSeenCount],
    CAST((SELECT COUNT(1) FROM [dbo].[MailboxPermissionBackfeedState] WHERE [IsDeleted] = 0) AS int) AS [TotalActiveCount],
    CAST((SELECT COUNT(1) FROM [dbo].[MailboxPermissionBackfeedState] WHERE [IsDeleted] = 1) AS int) AS [TotalDeletedCount],
    CAST((
        SELECT COUNT(1)
        FROM [SourceRows] AS s
        WHERE EXISTS (
            SELECT 1
            FROM [dbo].[MailboxPermissionBackfeedState] AS t
            WHERE t.[SourceSystem] = s.[SourceSystem]
              AND t.[PermissionType] = s.[PermissionType]
              AND t.[MailboxKey] = s.[MailboxKey]
              AND t.[TrusteeKey] = s.[TrusteeKey]
        )
    ) AS int) AS [CurrentRunInsertedOrSeenCount];
SET NOCOUNT ON;

DECLARE @ResolvedBackfeedRunId uniqueidentifier = TRY_CONVERT(uniqueidentifier, @BackfeedRunId);
DECLARE @ResolvedModifiedBy nvarchar(128) = COALESCE(NULLIF(@ModifiedBy, N''), N'AdeaJobEngine.Backfeed');

;WITH [CurrentRunSource] AS (
    SELECT
        s.[SourceSystem],
        s.[PermissionType],
        s.[MailboxKey],
        s.[MailboxName],
        s.[TrusteeKey],
        s.[TrusteeName],
        s.[TrusteeDomain],
        s.[ObjectClass],
        s.[AcePermissions],
        s.[DistinguishedName],
        s.[ExchHideFromAddressLists],
        s.[AdReferenceObjectGuid],
        s.[IsInherited],
        s.[Deny],
        s.[AccessRights],
        s.[RowHash],
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
        [MailboxName],
        [TrusteeKey],
        [TrusteeName],
        [TrusteeDomain],
        [ObjectClass],
        [AcePermissions],
        [DistinguishedName],
        [ExchHideFromAddressLists],
        [AdReferenceObjectGuid],
        [IsInherited],
        [Deny],
        [AccessRights],
        [RowHash]
    FROM [CurrentRunSource]
    WHERE [RowNumber] = 1
),
[MissingRows] AS (
    SELECT s.*
    FROM [SourceRows] AS s
    WHERE NOT EXISTS (
        SELECT 1
        FROM [dbo].[MailboxPermissionBackfeedState] AS t
        WHERE t.[SourceSystem] = s.[SourceSystem]
          AND t.[PermissionType] = s.[PermissionType]
          AND t.[MailboxKey] = s.[MailboxKey]
          AND t.[TrusteeKey] = s.[TrusteeKey]
    )
)
INSERT INTO [dbo].[MailboxPermissionBackfeedState]
(
    [SourceSystem],
    [PermissionType],
    [MailboxKey],
    [MailboxName],
    [TrusteeKey],
    [TrusteeName],
    [TrusteeDomain],
    [ObjectClass],
    [AcePermissions],
    [DistinguishedName],
    [ExchHideFromAddressLists],
    [AdReferenceObjectGuid],
    [IsInherited],
    [Deny],
    [AccessRights],
    [RowHash],
    [FirstSeenBackfeedRunId],
    [LastSeenBackfeedRunId],
    [FirstSeenAt],
    [LastSeenAt],
    [IsDeleted],
    [DeletedAt],
    [DeletedBackfeedRunId],
    [ModifiedOn],
    [ModifiedBy]
)
SELECT
    m.[SourceSystem],
    m.[PermissionType],
    m.[MailboxKey],
    m.[MailboxName],
    m.[TrusteeKey],
    m.[TrusteeName],
    m.[TrusteeDomain],
    m.[ObjectClass],
    m.[AcePermissions],
    m.[DistinguishedName],
    m.[ExchHideFromAddressLists],
    m.[AdReferenceObjectGuid],
    m.[IsInherited],
    m.[Deny],
    m.[AccessRights],
    m.[RowHash],
    @ResolvedBackfeedRunId,
    @ResolvedBackfeedRunId,
    SYSDATETIME(),
    SYSDATETIME(),
    CAST(0 AS bit),
    NULL,
    NULL,
    SYSDATETIME(),
    @ResolvedModifiedBy
FROM [MissingRows] AS m;

DECLARE @InsertedCount int = @@ROWCOUNT;
DECLARE @SourceCount int = (
    SELECT COUNT(1)
    FROM [SourceRows]
);

SELECT
    @InsertedCount AS [InsertedCount],
    CAST(0 AS int) AS [UpdatedCount],
    CAST(0 AS int) AS [DeletedCount],
    CAST(0 AS int) AS [ReactivatedCount],
    CASE
        WHEN @SourceCount >= @InsertedCount THEN @SourceCount - @InsertedCount
        ELSE 0
    END AS [UnchangedCount];
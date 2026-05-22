IF OBJECT_ID(N'[dbo].[stg_MailboxPermissions_Backfeed]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[stg_MailboxPermissions_Backfeed]
    (
        [Id] [int] IDENTITY(1,1) NOT NULL,
        [BackfeedRunId] [uniqueidentifier] NOT NULL,
        [SourceSystem] [nvarchar](50) NOT NULL,
        [PermissionType] [nvarchar](50) NOT NULL,
        [MailboxKey] [nvarchar](512) NOT NULL,
        [MailboxName] [nvarchar](512) NULL,
        [TrusteeKey] [nvarchar](512) NOT NULL,
        [TrusteeName] [nvarchar](512) NULL,
        [TrusteeDomain] [nvarchar](256) NULL,
        [ObjectClass] [nvarchar](128) NULL,
        [AcePermissions] [nvarchar](256) NOT NULL,
        [DistinguishedName] [nvarchar](2048) NULL,
        [ExchHideFromAddressLists] [bit] NULL,
        [AdReferenceObjectGuid] [uniqueidentifier] NULL,
        [IsInherited] [bit] NULL,
        [Deny] [bit] NULL,
        [AccessRights] [nvarchar](512) NULL,
        [RowHash] [nvarchar](128) NOT NULL,
        [StagingInserted] [datetime2] NOT NULL CONSTRAINT [DF_stg_MailboxPermissions_Backfeed_StagingInserted] DEFAULT (sysdatetime()),
        CONSTRAINT [PK_stg_MailboxPermissions_Backfeed] PRIMARY KEY CLUSTERED ([Id] ASC)
    );
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE [name] = N'IX_stg_MailboxPermissions_Backfeed_Run_BusinessKey'
      AND [object_id] = OBJECT_ID(N'[dbo].[stg_MailboxPermissions_Backfeed]')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_stg_MailboxPermissions_Backfeed_Run_BusinessKey]
        ON [dbo].[stg_MailboxPermissions_Backfeed]
        (
            [BackfeedRunId],
            [SourceSystem],
            [PermissionType],
            [MailboxKey],
            [TrusteeKey]
        );
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE [name] = N'IX_stg_MailboxPermissions_Backfeed_BusinessKey_RowHash'
      AND [object_id] = OBJECT_ID(N'[dbo].[stg_MailboxPermissions_Backfeed]')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_stg_MailboxPermissions_Backfeed_BusinessKey_RowHash]
        ON [dbo].[stg_MailboxPermissions_Backfeed]
        (
            [SourceSystem],
            [PermissionType],
            [MailboxKey],
            [TrusteeKey],
            [RowHash]
        );
END;

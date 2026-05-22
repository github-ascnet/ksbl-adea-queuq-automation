IF OBJECT_ID(N'[dbo].[MailboxPermissionBackfeedState]', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[MailboxPermissionBackfeedState]
    (
        [Id] [bigint] IDENTITY(1,1) NOT NULL,
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
        [RowHash] [char](64) NOT NULL,
        [FirstSeenBackfeedRunId] [uniqueidentifier] NOT NULL,
        [LastSeenBackfeedRunId] [uniqueidentifier] NOT NULL,
        [FirstSeenAt] [datetime2] NOT NULL CONSTRAINT [DF_MailboxPermissionBackfeedState_FirstSeenAt] DEFAULT (sysdatetime()),
        [LastSeenAt] [datetime2] NOT NULL CONSTRAINT [DF_MailboxPermissionBackfeedState_LastSeenAt] DEFAULT (sysdatetime()),
        [IsDeleted] [bit] NOT NULL CONSTRAINT [DF_MailboxPermissionBackfeedState_IsDeleted] DEFAULT ((0)),
        [DeletedAt] [datetime2] NULL,
        [DeletedBackfeedRunId] [uniqueidentifier] NULL,
        [ModifiedOn] [datetime2] NOT NULL CONSTRAINT [DF_MailboxPermissionBackfeedState_ModifiedOn] DEFAULT (sysdatetime()),
        [ModifiedBy] [nvarchar](128) NOT NULL CONSTRAINT [DF_MailboxPermissionBackfeedState_ModifiedBy] DEFAULT (N'AdeaJobEngine.Backfeed'),
        CONSTRAINT [PK_MailboxPermissionBackfeedState] PRIMARY KEY CLUSTERED ([Id] ASC)
    );
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE [name] = N'UX_MailboxPermissionBackfeedState_BusinessKey'
      AND [object_id] = OBJECT_ID(N'[dbo].[MailboxPermissionBackfeedState]')
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX [UX_MailboxPermissionBackfeedState_BusinessKey]
        ON [dbo].[MailboxPermissionBackfeedState]
        (
            [SourceSystem],
            [PermissionType],
            [MailboxKey],
            [TrusteeKey]
        );
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE [name] = N'IX_MailboxPermissionBackfeedState_LastSeenBackfeedRunId'
      AND [object_id] = OBJECT_ID(N'[dbo].[MailboxPermissionBackfeedState]')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_MailboxPermissionBackfeedState_LastSeenBackfeedRunId]
        ON [dbo].[MailboxPermissionBackfeedState]
        (
            [LastSeenBackfeedRunId]
        );
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE [name] = N'IX_MailboxPermissionBackfeedState_DeletedBackfeedRunId'
      AND [object_id] = OBJECT_ID(N'[dbo].[MailboxPermissionBackfeedState]')
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_MailboxPermissionBackfeedState_DeletedBackfeedRunId]
        ON [dbo].[MailboxPermissionBackfeedState]
        (
            [DeletedBackfeedRunId]
        );
END;
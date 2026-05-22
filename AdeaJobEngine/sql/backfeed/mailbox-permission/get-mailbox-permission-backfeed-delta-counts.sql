/*
    Phase 8.11 Delta-only counts for MailboxPermission Backfeed.

    Current MailboxPermissions schema in this workspace does not expose modern
    business key columns required for full Inserted/Updated/Deleted/Unchanged
    comparison by SourceSystem/PermissionType/MailboxKey/TrusteeKey/RowHash.

    Therefore this script returns a safe partial delta view:
      - InsertedCount   = staged row count for current BackfeedRunId
      - UpdatedCount    = 0
      - DeletedCount    = 0
      - UnchangedCount  = 0

    This script is SELECT-only and does not modify any table data.
*/

SELECT
    CAST(COUNT_BIG(1) AS int) AS InsertedCount,
    CAST(0 AS int) AS UpdatedCount,
    CAST(0 AS int) AS DeletedCount,
    CAST(0 AS int) AS UnchangedCount
FROM [dbo].[stg_MailboxPermissions_Backfeed] AS s
WHERE s.[BackfeedRunId] = TRY_CONVERT(uniqueidentifier, @BackfeedRunId);

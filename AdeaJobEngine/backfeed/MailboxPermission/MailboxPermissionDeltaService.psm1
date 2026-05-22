Set-StrictMode -Version Latest

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$engineRoot = Split-Path -Parent (Split-Path -Parent $moduleRoot)
Import-Module -Name (Join-Path -Path $engineRoot -ChildPath 'shared\Backfeed\BackfeedSqlScriptRunner.psm1') -Force -DisableNameChecking

function Get-MailboxPermissionDeltaSqlScriptPath {
    [CmdletBinding()]
    param()

    Join-Path -Path $engineRoot -ChildPath 'sql\backfeed\mailbox-permission\get-mailbox-permission-backfeed-delta-counts.sql'
}

function Get-MailboxPermissionStateSqlScriptPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ScriptName)

    Join-Path -Path $engineRoot -ChildPath (Join-Path -Path 'sql\backfeed\mailbox-permission' -ChildPath $ScriptName)
}

function Resolve-MailboxPermissionDeltaBackfeedRunId {
    [CmdletBinding()]
    param(
        [object]$BackfeedContext,
        [string]$BackfeedRunId
    )

    $candidate = [string]$BackfeedRunId
    if ([string]::IsNullOrWhiteSpace($candidate) -and $null -ne $BackfeedContext -and $BackfeedContext.PSObject.Properties['BackfeedRunId']) {
        $candidate = [string]$BackfeedContext.BackfeedRunId
    }

    $parsed = [guid]::Empty
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and [guid]::TryParse($candidate, [ref]$parsed)) {
        return $parsed.ToString()
    }

    ''
}

function ConvertTo-DeltaIntCount {
    [CmdletBinding()]
    param(
        [object]$InputObject,
        [string]$PropertyName
    )

    if ($null -eq $InputObject -or [string]::IsNullOrWhiteSpace($PropertyName)) {
        return 0
    }

    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property -or $null -eq $property.Value) {
        return 0
    }

    [int]$property.Value
}

function Invoke-MailboxPermissionBackfeedDeltaSql {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$BackfeedContext,
        [Parameter(Mandatory = $true)][string]$BackfeedRunId
    )

    $scriptPath = Get-MailboxPermissionDeltaSqlScriptPath
    Invoke-BackfeedSqlQueryScript -Context $BackfeedContext -ScriptPath $scriptPath -Parameters @{ BackfeedRunId = $BackfeedRunId }
}

function Invoke-MailboxPermissionBackfeedStateInitializationSql {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$BackfeedContext,
        [Parameter(Mandatory = $true)][string]$BackfeedRunId,
        [string]$ModifiedBy = 'AdeaJobEngine.Backfeed'
    )

    $createScriptPath = Get-MailboxPermissionStateSqlScriptPath -ScriptName 'create-mailbox-permission-backfeed-state.sql'
    $initializeScriptPath = Get-MailboxPermissionStateSqlScriptPath -ScriptName 'initialize-mailbox-permission-backfeed-state-insert-only.sql'

    $null = Invoke-BackfeedSqlScript -Context $BackfeedContext -ScriptPath $createScriptPath
    Invoke-BackfeedSqlQueryScript -Context $BackfeedContext -ScriptPath $initializeScriptPath -Parameters @{ BackfeedRunId = $BackfeedRunId; ModifiedBy = $ModifiedBy }
}

function Get-MailboxPermissionBackfeedDelta {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$BackfeedContext,
        [string]$BackfeedRunId
    )

    $resolvedBackfeedRunId = Resolve-MailboxPermissionDeltaBackfeedRunId -BackfeedContext $BackfeedContext -BackfeedRunId $BackfeedRunId
    if ([string]::IsNullOrWhiteSpace($resolvedBackfeedRunId)) {
        return [pscustomobject]@{
            Success        = $false
            BackfeedRunId  = [string]$BackfeedRunId
            InsertedCount  = 0
            UpdatedCount   = 0
            DeletedCount   = 0
            UnchangedCount = 0
            FailedCount    = 1
            Message        = 'BackfeedRunId is missing or invalid.'
            ErrorCode      = 'INVALID_BACKFEED_RUN_ID'
            Errors         = @([pscustomobject]@{ Message = 'BackfeedRunId is missing or invalid.'; ErrorCode = 'INVALID_BACKFEED_RUN_ID'; BackfeedRunId = [string]$BackfeedRunId })
        }
    }

    try {
        $queryResult = @(Invoke-MailboxPermissionBackfeedDeltaSql -BackfeedContext $BackfeedContext -BackfeedRunId $resolvedBackfeedRunId)
        $row = if ($queryResult.Count -gt 0) { $queryResult[0] } else { $null }

        $insertedCount = ConvertTo-DeltaIntCount -InputObject $row -PropertyName 'InsertedCount'
        $updatedCount = ConvertTo-DeltaIntCount -InputObject $row -PropertyName 'UpdatedCount'
        $deletedCount = ConvertTo-DeltaIntCount -InputObject $row -PropertyName 'DeletedCount'
        $unchangedCount = ConvertTo-DeltaIntCount -InputObject $row -PropertyName 'UnchangedCount'

        [pscustomobject]@{
            Success        = $true
            BackfeedRunId  = $resolvedBackfeedRunId
            InsertedCount  = $insertedCount
            UpdatedCount   = $updatedCount
            DeletedCount   = $deletedCount
            UnchangedCount = $unchangedCount
            FailedCount    = 0
            Message        = 'Delta counts resolved from SQL script.'
            ErrorCode      = $null
            Errors         = @()
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        [pscustomobject]@{
            Success        = $false
            BackfeedRunId  = $resolvedBackfeedRunId
            InsertedCount  = 0
            UpdatedCount   = 0
            DeletedCount   = 0
            UnchangedCount = 0
            FailedCount    = 1
            Message        = $errorMessage
            ErrorCode      = 'MAILBOX_PERMISSION_DELTA_FAILED'
            Errors         = @([pscustomobject]@{ Message = $errorMessage; ErrorCode = 'MAILBOX_PERMISSION_DELTA_FAILED'; BackfeedRunId = $resolvedBackfeedRunId })
        }
    }
}

function Initialize-MailboxPermissionBackfeedStateInsertOnly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$BackfeedContext,
        [string]$BackfeedRunId
    )

    $resolvedBackfeedRunId = Resolve-MailboxPermissionDeltaBackfeedRunId -BackfeedContext $BackfeedContext -BackfeedRunId $BackfeedRunId
    if ([string]::IsNullOrWhiteSpace($resolvedBackfeedRunId)) {
        return [pscustomobject]@{
            Success          = $false
            BackfeedRunId    = [string]$BackfeedRunId
            InsertedCount    = 0
            UpdatedCount     = 0
            DeletedCount     = 0
            ReactivatedCount = 0
            UnchangedCount   = 0
            FailedCount      = 1
            Message          = 'BackfeedRunId is missing or invalid.'
            ErrorCode        = 'INVALID_BACKFEED_RUN_ID'
            Errors           = @([pscustomobject]@{ Message = 'BackfeedRunId is missing or invalid.'; ErrorCode = 'INVALID_BACKFEED_RUN_ID'; BackfeedRunId = [string]$BackfeedRunId })
        }
    }

    try {
        $queryResult = @(Invoke-MailboxPermissionBackfeedStateInitializationSql -BackfeedContext $BackfeedContext -BackfeedRunId $resolvedBackfeedRunId)
        $row = if ($queryResult.Count -gt 0) { $queryResult[0] } else { $null }
        $isSimulated = $false
        if ($null -ne $row -and $row.PSObject.Properties['Simulated'] -and [bool]$row.Simulated) {
            $isSimulated = $true
        }

        [pscustomobject]@{
            Success          = $true
            Simulated        = $isSimulated
            BackfeedRunId    = $resolvedBackfeedRunId
            InsertedCount    = ConvertTo-DeltaIntCount -InputObject $row -PropertyName 'InsertedCount'
            UpdatedCount     = ConvertTo-DeltaIntCount -InputObject $row -PropertyName 'UpdatedCount'
            DeletedCount     = ConvertTo-DeltaIntCount -InputObject $row -PropertyName 'DeletedCount'
            ReactivatedCount = ConvertTo-DeltaIntCount -InputObject $row -PropertyName 'ReactivatedCount'
            UnchangedCount   = ConvertTo-DeltaIntCount -InputObject $row -PropertyName 'UnchangedCount'
            FailedCount      = 0
            Message          = if ($isSimulated) { 'State insert-only initialization simulated.' } else { 'State insert-only initialization completed.' }
            ErrorCode        = $null
            Errors           = @()
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        [pscustomobject]@{
            Success          = $false
            BackfeedRunId    = $resolvedBackfeedRunId
            InsertedCount    = 0
            UpdatedCount     = 0
            DeletedCount     = 0
            ReactivatedCount = 0
            UnchangedCount   = 0
            FailedCount      = 1
            Message          = $errorMessage
            ErrorCode        = 'MAILBOX_PERMISSION_STATE_INITIALIZE_FAILED'
            Errors           = @([pscustomobject]@{ Message = $errorMessage; ErrorCode = 'MAILBOX_PERMISSION_STATE_INITIALIZE_FAILED'; BackfeedRunId = $resolvedBackfeedRunId })
        }
    }
}

Export-ModuleMember -Function @(
    'Get-MailboxPermissionBackfeedDelta',
    'Invoke-MailboxPermissionBackfeedDeltaSql',
    'Resolve-MailboxPermissionDeltaBackfeedRunId',
    'Get-MailboxPermissionDeltaSqlScriptPath',
    'Get-MailboxPermissionStateSqlScriptPath',
    'Invoke-MailboxPermissionBackfeedStateInitializationSql',
    'Initialize-MailboxPermissionBackfeedStateInsertOnly'
)

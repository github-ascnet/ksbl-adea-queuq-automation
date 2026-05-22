Set-StrictMode -Version Latest

function Invoke-MailboxPermissionBackfeedSqlWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object[]]$Rows
    )

    [pscustomobject]@{ Simulated = $true; StagedCount = @($Rows).Count }
}

function Write-MailboxPermissionBackfeedStaging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$BackfeedContext,
        [Parameter(Mandatory = $true)][object[]]$Rows
    )

    $rowCount = @($Rows).Count
    if ($rowCount -eq 0) {
        return [pscustomobject]@{
            Success     = $true
            StagedCount = 0
            Message     = 'No rows to stage.'
            ErrorCode   = $null
        }
    }

    try {
        $null = Invoke-MailboxPermissionBackfeedSqlWrite -Context $BackfeedContext -Rows $Rows
        [pscustomobject]@{
            Success     = $true
            StagedCount = $rowCount
            Message     = 'Rows staged.'
            ErrorCode   = $null
        }
    }
    catch {
        [pscustomobject]@{
            Success     = $false
            StagedCount = 0
            Message     = $_.Exception.Message
            ErrorCode   = 'MAILBOX_PERMISSION_STAGE_FAILED'
        }
    }
}

Export-ModuleMember -Function @(
    'Write-MailboxPermissionBackfeedStaging',
    'Invoke-MailboxPermissionBackfeedSqlWrite'
)
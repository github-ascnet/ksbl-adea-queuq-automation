Set-StrictMode -Version Latest

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$engineRoot = Split-Path -Parent (Split-Path -Parent $moduleRoot)
Import-Module -Name (Join-Path -Path $engineRoot -ChildPath 'shared\Backfeed\BackfeedResult.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'MailboxPermissionSourceReader.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'MailboxPermissionMapper.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'MailboxPermissionStagingWriter.psm1') -Force -DisableNameChecking

function Invoke-MailboxPermissionBackfeed {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $startedAt = if ($Context.StartedAt) { [datetime]$Context.StartedAt } else { Get-Date }
    $rawPermissions = @()
    $rows = @()
    $stagedCount = 0

    try {
        $rawPermissions = @(Read-MailboxPermissionBackfeedSources -BackfeedContext $Context)
        $rows = @(ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $rawPermissions)

        $stageResult = Write-MailboxPermissionBackfeedStaging -BackfeedContext $Context -Rows $rows
        if ($null -ne $stageResult -and $stageResult.PSObject.Properties.Name -contains 'StagedCount') {
            $stagedCount = [int]$stageResult.StagedCount
        }

        if (-not $stageResult.Success) {
            $completedAt = Get-Date
            return New-BackfeedResult -BackfeedType 'MailboxPermission' -Mode ([string]$Context.Mode) -Status 'Failed' -ReadCount $rawPermissions.Count -StagedCount $stagedCount -InsertedCount 0 -UpdatedCount 0 -DeletedCount 0 -UnchangedCount 0 -FailedCount 1 -StartedAt $startedAt -CompletedAt $completedAt -DurationSeconds ([math]::Round(($completedAt - $startedAt).TotalSeconds, 3)) -Errors @([pscustomobject]@{ Message = [string]$stageResult.Message; ErrorCode = [string]$stageResult.ErrorCode })
        }

        $completedAt = Get-Date
        New-BackfeedResult -BackfeedType 'MailboxPermission' -Mode ([string]$Context.Mode) -Status 'Succeeded' -ReadCount $rawPermissions.Count -StagedCount $stagedCount -InsertedCount 0 -UpdatedCount 0 -DeletedCount 0 -UnchangedCount 0 -FailedCount 0 -StartedAt $startedAt -CompletedAt $completedAt -DurationSeconds ([math]::Round(($completedAt - $startedAt).TotalSeconds, 3)) -Errors @()
    }
    catch {
        $completedAt = Get-Date
        New-BackfeedResult -BackfeedType 'MailboxPermission' -Mode ([string]$Context.Mode) -Status 'Failed' -ReadCount $rawPermissions.Count -StagedCount $stagedCount -InsertedCount 0 -UpdatedCount 0 -DeletedCount 0 -UnchangedCount 0 -FailedCount 1 -StartedAt $startedAt -CompletedAt $completedAt -DurationSeconds ([math]::Round(($completedAt - $startedAt).TotalSeconds, 3)) -Errors @([pscustomobject]@{ Message = $_.Exception.Message; ErrorCode = 'MAILBOX_PERMISSION_BACKFEED_FAILED' })
    }
}

Export-ModuleMember -Function @('Invoke-MailboxPermissionBackfeed')
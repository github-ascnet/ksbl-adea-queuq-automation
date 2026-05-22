Set-StrictMode -Version Latest

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'MailboxPermissionSourceReader.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'MailboxPermissionMapper.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'MailboxPermissionStagingWriter.psm1') -Force -DisableNameChecking

function Invoke-MailboxPermissionBackfeed {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $startedAt = if ($Context.StartedAt) { [datetime]$Context.StartedAt } else { Get-Date }
    $completedAt = Get-Date

    try {
        $rawPermissions = @(Read-MailboxPermissionBackfeedSources -BackfeedContext $Context)
        $rows = @(ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $rawPermissions)
        $stageResult = Write-MailboxPermissionBackfeedStaging -BackfeedContext $Context -Rows $rows

        if (-not $stageResult.Success) {
            $completedAt = Get-Date
            return New-BackfeedResult -BackfeedType 'MailboxPermission' -Mode ([string]$Context.Mode) -Status 'Failed' -ReadCount $rawPermissions.Count -StagedCount $stageResult.StagedCount -FailedCount 1 -StartedAt $startedAt -CompletedAt $completedAt -DurationSeconds ([math]::Round(($completedAt - $startedAt).TotalSeconds, 3)) -Errors @([pscustomobject]@{ Message = $stageResult.Message; ErrorCode = $stageResult.ErrorCode })
        }

        $completedAt = Get-Date
        New-BackfeedResult -BackfeedType 'MailboxPermission' -Mode ([string]$Context.Mode) -Status 'Succeeded' -ReadCount $rawPermissions.Count -StagedCount $stageResult.StagedCount -FailedCount 0 -StartedAt $startedAt -CompletedAt $completedAt -DurationSeconds ([math]::Round(($completedAt - $startedAt).TotalSeconds, 3)) -Errors @()
    }
    catch {
        $completedAt = Get-Date
        New-BackfeedResult -BackfeedType 'MailboxPermission' -Mode ([string]$Context.Mode) -Status 'Failed' -ReadCount 0 -StagedCount 0 -FailedCount 1 -StartedAt $startedAt -CompletedAt $completedAt -DurationSeconds ([math]::Round(($completedAt - $startedAt).TotalSeconds, 3)) -Errors @([pscustomobject]@{ Message = $_.Exception.Message; ErrorCode = 'MAILBOX_PERMISSION_BACKFEED_FAILED' })
    }
}

Export-ModuleMember -Function @('Invoke-MailboxPermissionBackfeed')
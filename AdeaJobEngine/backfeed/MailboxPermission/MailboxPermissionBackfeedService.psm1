Set-StrictMode -Version Latest

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$engineRoot = Split-Path -Parent (Split-Path -Parent $moduleRoot)
Import-Module -Name (Join-Path -Path $engineRoot -ChildPath 'shared\Backfeed\BackfeedResult.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'MailboxPermissionSourceReader.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'MailboxPermissionMapper.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'MailboxPermissionStagingWriter.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path -Path $moduleRoot -ChildPath 'MailboxPermissionDeltaService.psm1') -Force -DisableNameChecking

function Invoke-MailboxPermissionBackfeed {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $startedAt = if ($Context.StartedAt) { [datetime]$Context.StartedAt } else { Get-Date }
    $resultBackfeedRunId = if ($Context.PSObject.Properties['BackfeedRunId']) { [string]$Context.BackfeedRunId } else { '' }
    $rawPermissions = @()
    $rows = @()
    $stagedCount = 0
    $insertedCount = 0
    $updatedCount = 0
    $deletedCount = 0
    $unchangedCount = 0

    try {
        $rawPermissions = @(Read-MailboxPermissionBackfeedSources -BackfeedContext $Context)
        $rows = @(ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $rawPermissions)

        $stageResult = Write-MailboxPermissionBackfeedStaging -BackfeedContext $Context -Rows $rows
        if ($null -ne $stageResult -and $stageResult.PSObject.Properties.Name -contains 'BackfeedRunId' -and -not [string]::IsNullOrWhiteSpace([string]$stageResult.BackfeedRunId)) {
            $resultBackfeedRunId = [string]$stageResult.BackfeedRunId
        }
        if ($null -ne $stageResult -and $stageResult.PSObject.Properties.Name -contains 'StagedCount') {
            $stagedCount = [int]$stageResult.StagedCount
        }

        if (-not $stageResult.Success) {
            $completedAt = Get-Date
            $stageErrors = @()
            if ($null -ne $stageResult -and $stageResult.PSObject.Properties.Name -contains 'Errors') {
                $stageErrors = @($stageResult.Errors)
            }
            if ($stageErrors.Count -eq 0) {
                $stageErrors = @([pscustomobject]@{
                        Message       = [string]$stageResult.Message
                        ErrorCode     = [string]$stageResult.ErrorCode
                        CorrelationId = [string]$Context.CorrelationId
                        BackfeedRunId = $resultBackfeedRunId
                    })
            }

            return New-BackfeedResult -BackfeedRunId $resultBackfeedRunId -BackfeedType 'MailboxPermission' -Mode ([string]$Context.Mode) -Status 'Failed' -ReadCount $rawPermissions.Count -StagedCount $stagedCount -InsertedCount $insertedCount -UpdatedCount $updatedCount -DeletedCount $deletedCount -UnchangedCount $unchangedCount -FailedCount 1 -StartedAt $startedAt -CompletedAt $completedAt -DurationSeconds ([math]::Round(($completedAt - $startedAt).TotalSeconds, 3)) -Errors $stageErrors
        }

        $deltaResult = Get-MailboxPermissionBackfeedDelta -BackfeedContext $Context -BackfeedRunId $resultBackfeedRunId
        if ($null -ne $deltaResult -and $deltaResult.PSObject.Properties.Name -contains 'BackfeedRunId' -and -not [string]::IsNullOrWhiteSpace([string]$deltaResult.BackfeedRunId)) {
            $resultBackfeedRunId = [string]$deltaResult.BackfeedRunId
        }
        if ($null -ne $deltaResult -and $deltaResult.PSObject.Properties.Name -contains 'InsertedCount') { $insertedCount = [int]$deltaResult.InsertedCount }
        if ($null -ne $deltaResult -and $deltaResult.PSObject.Properties.Name -contains 'UpdatedCount') { $updatedCount = [int]$deltaResult.UpdatedCount }
        if ($null -ne $deltaResult -and $deltaResult.PSObject.Properties.Name -contains 'DeletedCount') { $deletedCount = [int]$deltaResult.DeletedCount }
        if ($null -ne $deltaResult -and $deltaResult.PSObject.Properties.Name -contains 'UnchangedCount') { $unchangedCount = [int]$deltaResult.UnchangedCount }

        if ($null -eq $deltaResult -or -not $deltaResult.Success) {
            $completedAt = Get-Date
            $deltaErrors = @()
            if ($null -ne $deltaResult -and $deltaResult.PSObject.Properties.Name -contains 'Errors') {
                $deltaErrors = @($deltaResult.Errors)
            }
            if ($deltaErrors.Count -eq 0) {
                $deltaMessage = if ($null -ne $deltaResult -and $deltaResult.PSObject.Properties.Name -contains 'Message') { [string]$deltaResult.Message } else { 'Delta calculation failed.' }
                $deltaErrorCode = if ($null -ne $deltaResult -and $deltaResult.PSObject.Properties.Name -contains 'ErrorCode') { [string]$deltaResult.ErrorCode } else { 'MAILBOX_PERMISSION_DELTA_FAILED' }
                $deltaErrors = @([pscustomobject]@{
                        Message       = $deltaMessage
                        ErrorCode     = $deltaErrorCode
                        CorrelationId = [string]$Context.CorrelationId
                        BackfeedRunId = $resultBackfeedRunId
                    })
            }

            return New-BackfeedResult -BackfeedRunId $resultBackfeedRunId -BackfeedType 'MailboxPermission' -Mode ([string]$Context.Mode) -Status 'Failed' -ReadCount $rawPermissions.Count -StagedCount $stagedCount -InsertedCount $insertedCount -UpdatedCount $updatedCount -DeletedCount $deletedCount -UnchangedCount $unchangedCount -FailedCount 1 -StartedAt $startedAt -CompletedAt $completedAt -DurationSeconds ([math]::Round(($completedAt - $startedAt).TotalSeconds, 3)) -Errors $deltaErrors
        }

        $stateInitializationResult = Initialize-MailboxPermissionBackfeedStateInsertOnly -BackfeedContext $Context -BackfeedRunId $resultBackfeedRunId
        $stateInitializationIsSimulated = $false
        if ($null -ne $stateInitializationResult -and $stateInitializationResult.PSObject.Properties.Name -contains 'Simulated') {
            $stateInitializationIsSimulated = [bool]$stateInitializationResult.Simulated
        }
        if ($null -ne $stateInitializationResult -and $stateInitializationResult.PSObject.Properties.Name -contains 'BackfeedRunId' -and -not [string]::IsNullOrWhiteSpace([string]$stateInitializationResult.BackfeedRunId)) {
            $resultBackfeedRunId = [string]$stateInitializationResult.BackfeedRunId
        }
        if (-not $stateInitializationIsSimulated -and $null -ne $stateInitializationResult -and $stateInitializationResult.PSObject.Properties.Name -contains 'InsertedCount') { $insertedCount = [int]$stateInitializationResult.InsertedCount }
        if (-not $stateInitializationIsSimulated -and $null -ne $stateInitializationResult -and $stateInitializationResult.PSObject.Properties.Name -contains 'UpdatedCount') { $updatedCount = [int]$stateInitializationResult.UpdatedCount }
        if (-not $stateInitializationIsSimulated -and $null -ne $stateInitializationResult -and $stateInitializationResult.PSObject.Properties.Name -contains 'DeletedCount') { $deletedCount = [int]$stateInitializationResult.DeletedCount }
        if (-not $stateInitializationIsSimulated -and $unchangedCount -eq 0 -and $null -ne $stateInitializationResult -and $stateInitializationResult.PSObject.Properties.Name -contains 'UnchangedCount') {
            $unchangedCount = [int]$stateInitializationResult.UnchangedCount
        }

        if ($null -eq $stateInitializationResult -or -not $stateInitializationResult.Success) {
            $completedAt = Get-Date
            $stateErrors = @()
            if ($null -ne $stateInitializationResult -and $stateInitializationResult.PSObject.Properties.Name -contains 'Errors') {
                $stateErrors = @($stateInitializationResult.Errors)
            }
            if ($stateErrors.Count -eq 0) {
                $stateMessage = if ($null -ne $stateInitializationResult -and $stateInitializationResult.PSObject.Properties.Name -contains 'Message') { [string]$stateInitializationResult.Message } else { 'State initialization failed.' }
                $stateErrorCode = if ($null -ne $stateInitializationResult -and $stateInitializationResult.PSObject.Properties.Name -contains 'ErrorCode') { [string]$stateInitializationResult.ErrorCode } else { 'MAILBOX_PERMISSION_STATE_INITIALIZE_FAILED' }
                $stateErrors = @([pscustomobject]@{
                        Message       = $stateMessage
                        ErrorCode     = $stateErrorCode
                        CorrelationId = [string]$Context.CorrelationId
                        BackfeedRunId = $resultBackfeedRunId
                    })
            }

            return New-BackfeedResult -BackfeedRunId $resultBackfeedRunId -BackfeedType 'MailboxPermission' -Mode ([string]$Context.Mode) -Status 'Failed' -ReadCount $rawPermissions.Count -StagedCount $stagedCount -InsertedCount $insertedCount -UpdatedCount $updatedCount -DeletedCount $deletedCount -UnchangedCount $unchangedCount -FailedCount 1 -StartedAt $startedAt -CompletedAt $completedAt -DurationSeconds ([math]::Round(($completedAt - $startedAt).TotalSeconds, 3)) -Errors $stateErrors
        }

        $completedAt = Get-Date
        New-BackfeedResult -BackfeedRunId $resultBackfeedRunId -BackfeedType 'MailboxPermission' -Mode ([string]$Context.Mode) -Status 'Succeeded' -ReadCount $rawPermissions.Count -StagedCount $stagedCount -InsertedCount $insertedCount -UpdatedCount $updatedCount -DeletedCount $deletedCount -UnchangedCount $unchangedCount -FailedCount 0 -StartedAt $startedAt -CompletedAt $completedAt -DurationSeconds ([math]::Round(($completedAt - $startedAt).TotalSeconds, 3)) -Errors @()
    }
    catch {
        $completedAt = Get-Date
        New-BackfeedResult -BackfeedRunId $resultBackfeedRunId -BackfeedType 'MailboxPermission' -Mode ([string]$Context.Mode) -Status 'Failed' -ReadCount $rawPermissions.Count -StagedCount $stagedCount -InsertedCount 0 -UpdatedCount 0 -DeletedCount 0 -UnchangedCount 0 -FailedCount 1 -StartedAt $startedAt -CompletedAt $completedAt -DurationSeconds ([math]::Round(($completedAt - $startedAt).TotalSeconds, 3)) -Errors @([pscustomobject]@{ Message = $_.Exception.Message; ErrorCode = 'MAILBOX_PERMISSION_BACKFEED_FAILED'; BackfeedRunId = $resultBackfeedRunId })
    }
}

Export-ModuleMember -Function @('Invoke-MailboxPermissionBackfeed')
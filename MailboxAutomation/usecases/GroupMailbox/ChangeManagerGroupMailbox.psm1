Set-StrictMode -Version Latest

function Invoke-ChangeManagerGroupMailbox {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','ManagerAdObjectName','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        $results = @()
        $failedResults = @()

        foreach ($row in $rows) {
            Write-LogInfo -Logger $Context.Logger -Message "Processing GroupMailbox.ChangeManager for '$($row.AdObjectName)' with manager '$($row.ManagerAdObjectName)'."

            $serviceResult = & $Context.Services.GroupMailbox.ChangeManager $Context $row
            $results += $serviceResult

            # If the mailbox is in a transient migration state, schedule a retry for the entire job.
            # For multi-row jobs: the first row returning RequiresRetry wins; remaining rows are skipped.
            if ($serviceResult.RequiresRetry) {
                $retryMinutes = if ($serviceResult.PSObject.Properties['RetryAfterMinutes'] -and $serviceResult.RetryAfterMinutes) { [int]$serviceResult.RetryAfterMinutes } else { 15 }
                $retryAfter   = (Get-Date).AddMinutes($retryMinutes)
                Write-LogWarn -Logger $Context.Logger -Message "GroupMailbox.ChangeManager: transient migration state for '$($row.AdObjectName)'. Scheduling retry after $retryMinutes minutes."
                return New-JobRetryResult -Message "GroupMailbox.ChangeManager: transient migration state. $($serviceResult.Message)" -RetryAfter $retryAfter -Output $results
            }

            if (-not $serviceResult.Success) {
                $failedResults += $serviceResult
                Write-LogWarn -Logger $Context.Logger -Message "GroupMailbox.ChangeManager failed for '$($row.AdObjectName)': $($serviceResult.Message)"
            }
            else {
                Write-LogInfo -Logger $Context.Logger -Message "GroupMailbox.ChangeManager completed for '$($row.AdObjectName)': $($serviceResult.Message)"
            }
        }

        if ($failedResults.Count -gt 0) {
            return New-JobFailedResult -Message "GroupMailbox.ChangeManager failed for $($failedResults.Count) of $($rows.Count) row(s)." -ErrorCode 'GROUP_MAILBOX_CHANGE_MANAGER_FAILED' -Output $results
        }

        return New-JobSucceededResult -Message "GroupMailbox.ChangeManager processed $($rows.Count) row(s)." -Output $results
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message 'Invoke-ChangeManagerGroupMailbox failed.' -Exception $_.Exception
        return New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-ChangeManagerGroupMailbox')

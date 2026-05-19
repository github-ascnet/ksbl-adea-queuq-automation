Set-StrictMode -Version Latest

function Invoke-AddEmailNickname {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context
    )

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @(
            'ActionType',
            'AdObjectName',
            'NewPrimaryEMailAddress',
            'CurrentUserName',
            'CurrentUserDomainName',
            'CurrentUserEMailAddress'
        )

        $results = @()
        $failedResults = @()

        foreach ($row in $rows) {
            Write-LogInfo -Logger $Context.Logger -Message "Processing GenericUser.AddEmailNickname for '$($row.AdObjectName)' with new primary SMTP address '$($row.NewPrimaryEMailAddress)'."

            $serviceResult = & $Context.Services.UserProvisioning.AddEmailNickname $Context $row
            $results += $serviceResult

            # RequiresRetry: mailbox in transient migration state — schedule job retry
            if ($serviceResult -and $serviceResult.PSObject.Properties['RequiresRetry'] -and [bool]$serviceResult.RequiresRetry) {
                $retryMinutes = if ($serviceResult.PSObject.Properties['RetryAfterMinutes'] -and $serviceResult.RetryAfterMinutes) { [int]$serviceResult.RetryAfterMinutes } else { 15 }
                $retryAfter = (Get-Date).AddMinutes($retryMinutes)
                Write-LogWarn -Logger $Context.Logger -Message "GenericUser.AddEmailNickname: transient migration state for '$($row.AdObjectName)'. Scheduling retry after $retryMinutes minutes."
                return New-JobRetryResult `
                    -Message "GenericUser.AddEmailNickname: transient migration state for '$($row.AdObjectName)'. $($serviceResult.Message)" `
                    -RetryAfter $retryAfter `
                    -Output $results
            }

            if (-not $serviceResult.Success) {
                $failedResults += $serviceResult
                Write-LogWarn -Logger $Context.Logger -Message "GenericUser.AddEmailNickname failed for '$($row.AdObjectName)': $($serviceResult.Message)"
            }
            else {
                Write-LogInfo -Logger $Context.Logger -Message "GenericUser.AddEmailNickname completed for '$($row.AdObjectName)': $($serviceResult.Message)"
            }
        }

        if ($failedResults.Count -gt 0) {
            $message = "GenericUser.AddEmailNickname failed for $($failedResults.Count) of $($rows.Count) row(s)."
            return New-JobFailedResult -Message $message -ErrorCode 'ADD_EMAIL_NICKNAME_FAILED' -Output $results
        }

        return New-JobSucceededResult -Message "GenericUser.AddEmailNickname processed $($rows.Count) row(s)." -Output $results
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message 'Invoke-AddEmailNickname failed.' -Exception $_.Exception
        return New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-AddEmailNickname')

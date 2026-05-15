Set-StrictMode -Version Latest

function Invoke-EnableGenericUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context
    )

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        $results = @()
        $failedResults = @()

        foreach ($row in $rows) {
            Write-LogInfo -Logger $Context.Logger -Message "Processing GenericUser.Enable for '$($row.AdObjectName)'."

            $serviceResult = & $Context.Services.UserProvisioning.EnableUser $Context $row

            # NOTE: Rows already processed in this batch must be idempotent on retry (AD Enable is idempotent).
            if ($serviceResult -and $serviceResult.PSObject.Properties['RequiresRetry'] -and [bool]$serviceResult.RequiresRetry) {
                $retryMinutes = if ($serviceResult.PSObject.Properties['RetryAfterMinutes'] -and $serviceResult.RetryAfterMinutes) { [int]$serviceResult.RetryAfterMinutes } else { 15 }
                $retryAfter = (Get-Date).AddMinutes($retryMinutes)
                Write-LogWarn -Logger $Context.Logger -Message "GenericUser.Enable for '$($row.AdObjectName)' requires retry after $retryMinutes minutes: $($serviceResult.Message)"
                return New-JobRetryResult -Message "GenericUser.Enable retry required for '$($row.AdObjectName)': $($serviceResult.Message)" -RetryAfter $retryAfter -Output @{
                    SuccessCount = $results.Count
                    FailedRows   = @($row.AdObjectName)
                }
            }

            $results += $serviceResult

            if (-not $serviceResult.Success) {
                $failedResults += $serviceResult
                Write-LogWarn -Logger $Context.Logger -Message "GenericUser.Enable failed for '$($row.AdObjectName)': $($serviceResult.Message)"
            }
            else {
                Write-LogInfo -Logger $Context.Logger -Message "GenericUser.Enable completed for '$($row.AdObjectName)': $($serviceResult.Message)"
            }
        }

        if ($failedResults.Count -gt 0) {
            $message = "GenericUser.Enable failed for $($failedResults.Count) of $($rows.Count) row(s)."
            return New-JobFailedResult -Message $message -ErrorCode 'ENABLE_GENERIC_USER_FAILED' -Output $results
        }

        return New-JobSucceededResult -Message "GenericUser.Enable processed $($rows.Count) row(s)." -Output $results
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message 'Invoke-EnableGenericUser failed.' -Exception $_.Exception
        return New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-EnableGenericUser')

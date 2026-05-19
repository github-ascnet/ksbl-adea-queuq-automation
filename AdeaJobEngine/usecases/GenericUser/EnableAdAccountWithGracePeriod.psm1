Set-StrictMode -Version Latest

function Invoke-EnableAdAccountWithGracePeriod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context
    )

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','TargetAdObjectName','GracePeriod','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        $results = @()
        $failedResults = @()

        foreach ($row in $rows) {
            Write-LogInfo -Logger $Context.Logger -Message "Processing GenericUser.EnableAdAccountWithGracePeriod for '$($row.AdObjectName)'."

            $serviceResult = & $Context.Services.UserProvisioning.EnableWithGracePeriod $Context $row
            $results += $serviceResult

            if (-not $serviceResult.Success) {
                $failedResults += $serviceResult
                Write-LogWarn -Logger $Context.Logger -Message "GenericUser.EnableAdAccountWithGracePeriod failed for '$($row.AdObjectName)': $($serviceResult.Message)"
            }
            else {
                Write-LogInfo -Logger $Context.Logger -Message "GenericUser.EnableAdAccountWithGracePeriod completed for '$($row.AdObjectName)': $($serviceResult.Message)"
            }
        }

        if ($failedResults.Count -gt 0) {
            $message = "GenericUser.EnableAdAccountWithGracePeriod failed for $($failedResults.Count) of $($rows.Count) row(s)."
            return New-JobFailedResult -Message $message -ErrorCode 'ENABLE_WITH_GRACE_PERIOD_FAILED' -Output $results
        }

        return New-JobSucceededResult -Message "GenericUser.EnableAdAccountWithGracePeriod processed $($rows.Count) row(s)." -Output $results
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message 'Invoke-EnableAdAccountWithGracePeriod failed.' -Exception $_.Exception
        return New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-EnableAdAccountWithGracePeriod')

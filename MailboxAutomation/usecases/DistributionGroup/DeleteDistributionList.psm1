Set-StrictMode -Version Latest

function Invoke-DeleteDistributionList {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        $results       = @()
        $failedResults = @()

        foreach ($row in $rows) {
            Write-LogInfo -Logger $Context.Logger -Message "Processing DistributionGroup.Delete for '$($row.AdObjectName)'."

            $serviceResult  = & $Context.Services.DistributionGroup.Delete $Context $row
            $results       += $serviceResult

            if (-not $serviceResult.Success) {
                $failedResults += $serviceResult
                Write-LogWarn -Logger $Context.Logger -Message "DistributionGroup.Delete failed for '$($row.AdObjectName)': $($serviceResult.Message)"
            }
            else {
                Write-LogInfo -Logger $Context.Logger -Message "DistributionGroup.Delete completed for '$($row.AdObjectName)': $($serviceResult.Message)"
            }
        }

        if ($failedResults.Count -gt 0) {
            return New-JobFailedResult -Message "DistributionGroup.Delete failed for $($failedResults.Count) of $($rows.Count) row(s)." -ErrorCode 'DISTRIBUTION_GROUP_DELETE_FAILED' -Output $results
        }

        return New-JobSucceededResult -Message "DistributionGroup.Delete processed $($rows.Count) row(s)." -Output $results
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message 'Invoke-DeleteDistributionList failed.' -Exception $_.Exception
        return New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-DeleteDistributionList')

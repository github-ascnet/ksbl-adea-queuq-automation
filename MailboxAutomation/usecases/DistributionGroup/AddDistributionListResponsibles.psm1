Set-StrictMode -Version Latest

function Invoke-AddDistributionListResponsibles {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','ManagedByMembers','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        $results = @()
        $failedResults = @()

        foreach ($row in $rows) {
            Write-LogInfo -Logger $Context.Logger -Message "Processing DistributionGroup.AddResponsibles for '$($row.AdObjectName)'."

            $serviceResult = & $Context.Services.DistributionGroup.AddResponsibles $Context $row
            $results += $serviceResult

            if (-not $serviceResult.Success) {
                $failedResults += $serviceResult
                Write-LogWarn -Logger $Context.Logger -Message "DistributionGroup.AddResponsibles failed for '$($row.AdObjectName)': $($serviceResult.Message)"
            }
            else {
                Write-LogInfo -Logger $Context.Logger -Message "DistributionGroup.AddResponsibles completed for '$($row.AdObjectName)': $($serviceResult.Message)"
            }
        }

        if ($failedResults.Count -gt 0) {
            return New-JobFailedResult -Message "DistributionGroup.AddResponsibles failed for $($failedResults.Count) of $($rows.Count) row(s)." -ErrorCode 'DISTRIBUTION_GROUP_ADD_RESPONSIBLES_FAILED' -Output $results
        }

        return New-JobSucceededResult -Message "DistributionGroup.AddResponsibles processed $($rows.Count) row(s)." -Output $results
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message 'Invoke-AddDistributionListResponsibles failed.' -Exception $_.Exception
        return New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-AddDistributionListResponsibles')

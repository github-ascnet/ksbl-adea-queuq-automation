Set-StrictMode -Version Latest

function Invoke-CreateDistributionGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','DisplayName','PrimarySmtpAddress','AdObjectName','OrgUnit','HideInAb','Manager','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        $results       = @()
        $failedResults = @()

        foreach ($row in $rows) {
            Write-LogInfo -Logger $Context.Logger -Message "Processing DistributionGroup.Create for '$($row.DisplayName)' / '$($row.PrimarySmtpAddress)'."

            $serviceResult  = & $Context.Services.DistributionGroup.Create $Context $row
            $results       += $serviceResult

            if (-not $serviceResult.Success) {
                $failedResults += $serviceResult
                Write-LogWarn -Logger $Context.Logger -Message "DistributionGroup.Create failed for '$($row.DisplayName)': $($serviceResult.Message)"
            }
            else {
                Write-LogInfo -Logger $Context.Logger -Message "DistributionGroup.Create completed for '$($row.DisplayName)': $($serviceResult.Message)"
            }
        }

        if ($failedResults.Count -gt 0) {
            return New-JobFailedResult -Message "DistributionGroup.Create failed for $($failedResults.Count) of $($rows.Count) row(s)." -ErrorCode 'DISTRIBUTION_GROUP_CREATE_FAILED' -Output $results
        }

        return New-JobSucceededResult -Message "DistributionGroup.Create processed $($rows.Count) row(s)." -Output $results
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message 'Invoke-CreateDistributionGroup failed.' -Exception $_.Exception
        return New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-CreateDistributionGroup')

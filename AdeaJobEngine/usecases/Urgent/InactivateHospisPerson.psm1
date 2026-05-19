Set-StrictMode -Version Latest

function Invoke-InactivateHospisPerson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context
    )

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @(
            'ActionType',
            'PersId',
            'DisplayName',
            'MigrateUser',
            'CurrentUserName',
            'CurrentUserDomainName',
            'CurrentUserEMailAddress'
        )

        $results = @()
        $failedResults = @()

        foreach ($row in $rows) {
            Write-LogInfo -Logger $Context.Logger -Message "Processing Urgent.InactivateHospisPerson for PersId '$($row.PersId)' / '$($row.DisplayName)'."

            $serviceResult = & $Context.Services.HospisPerson.UrgentInactivation $Context $row
            $results += $serviceResult

            if (-not $serviceResult.Success) {
                $failedResults += $serviceResult
                Write-LogWarn -Logger $Context.Logger -Message "Urgent.InactivateHospisPerson failed for PersId '$($row.PersId)': $($serviceResult.Message)"
            }
            else {
                Write-LogInfo -Logger $Context.Logger -Message "Urgent.InactivateHospisPerson completed for PersId '$($row.PersId)': $($serviceResult.Message)"
            }
        }

        if ($failedResults.Count -gt 0) {
            return New-JobFailedResult -Message "Urgent.InactivateHospisPerson failed for $($failedResults.Count) of $($rows.Count) row(s)." -ErrorCode 'URGENT_HOSPIS_INACTIVATION_FAILED' -Output $results
        }

        return New-JobSucceededResult -Message "Urgent.InactivateHospisPerson processed $($rows.Count) row(s)." -Output $results
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message 'Invoke-InactivateHospisPerson failed.' -Exception $_.Exception
        return New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-InactivateHospisPerson')

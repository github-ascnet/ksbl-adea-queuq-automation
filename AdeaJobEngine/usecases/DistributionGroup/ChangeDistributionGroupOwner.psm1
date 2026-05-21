Set-StrictMode -Version Latest

function Invoke-ChangeDistributionGroupOwner {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        $hasGroupIdentity = $rows[0].PSObject.Properties.Name -contains 'GroupIdentity'
        $hasOwnerIdentity = $rows[0].PSObject.Properties.Name -contains 'OwnerIdentity'
        $hasAdObjectName = $rows[0].PSObject.Properties.Name -contains 'AdObjectName'
        $hasManagedByMembers = $rows[0].PSObject.Properties.Name -contains 'ManagedByMembers'

        if ($hasGroupIdentity -and $hasOwnerIdentity) {
            Assert-RequiredCsvFields -Rows $rows -RequiredFields @('GroupIdentity', 'OwnerIdentity')
        }
        elseif ($hasAdObjectName -and $hasManagedByMembers) {
            Assert-RequiredCsvFields -Rows $rows -RequiredFields @('AdObjectName', 'ManagedByMembers')
        }
        else {
            throw 'ChangeDistributionGroupOwner requires GroupIdentity/OwnerIdentity or AdObjectName/ManagedByMembers.'
        }

        $results = @()
        $failedResults = @()

        foreach ($row in $rows) {
            $groupIdentity = if ($row.PSObject.Properties['GroupIdentity']) { [string]$row.GroupIdentity } else { [string]$row.AdObjectName }
            Write-LogInfo -Logger $Context.Logger -Message "Processing DistributionGroup.ChangeOwner for '$groupIdentity'."

            $serviceResult = Update-DistributionGroupManagedByMembers -Context $Context -Data $row
            $results += $serviceResult

            if (-not $serviceResult.Success) {
                $failedResults += $serviceResult
                Write-LogWarn -Logger $Context.Logger -Message "DistributionGroup.ChangeOwner failed for '$groupIdentity': $($serviceResult.Message)"
            }
            else {
                Write-LogInfo -Logger $Context.Logger -Message "DistributionGroup.ChangeOwner completed for '$groupIdentity': $($serviceResult.Message)"
            }
        }

        if ($failedResults.Count -gt 0) {
            return New-JobFailedResult -Message "DistributionGroup.ChangeOwner failed for $($failedResults.Count) of $($rows.Count) row(s)." -ErrorCode 'DISTRIBUTION_GROUP_CHANGE_OWNER_FAILED' -Output $results
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-ChangeDistributionGroupOwner processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-ChangeDistributionGroupOwner succeeded." -Output $results
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-ChangeDistributionGroupOwner failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-ChangeDistributionGroupOwner')

Set-StrictMode -Version Latest

function Invoke-CreateMultiFunctionGenericUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','TargetAdObjectName','TargetDomain','TargetUserAdDisplayname','TargetUserAdEmployeeType','Description','Manager','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        $results = @()
        $failedResults = @()

        foreach ($row in $rows) {
            Write-LogInfo -Logger $Context.Logger -Message "Processing GenericUser.CreateMultiFunction for '$($row.TargetAdObjectName)'."

            $serviceResult = & $Context.Services.UserProvisioning.NewUser $Context $row
            $results += $serviceResult

            if (-not $serviceResult.Success) {
                $failedResults += $serviceResult
                Write-LogWarn -Logger $Context.Logger -Message "GenericUser.CreateMultiFunction failed for '$($row.TargetAdObjectName)': $($serviceResult.Message)"
            }
            else {
                Write-LogInfo -Logger $Context.Logger -Message "GenericUser.CreateMultiFunction completed for '$($row.TargetAdObjectName)': $($serviceResult.Message)"
            }
        }

        if ($failedResults.Count -gt 0) {
            return New-JobFailedResult -Message "GenericUser.CreateMultiFunction failed for $($failedResults.Count) of $($rows.Count) row(s)." -ErrorCode 'GENERIC_USER_CREATE_MULTIFUNCTION_FAILED' -Output $results
        }

        return New-JobSucceededResult -Message "GenericUser.CreateMultiFunction processed $($rows.Count) row(s)." -Output $results
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message 'Invoke-CreateMultiFunctionGenericUser failed.' -Exception $_.Exception
        return New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-CreateMultiFunctionGenericUser')

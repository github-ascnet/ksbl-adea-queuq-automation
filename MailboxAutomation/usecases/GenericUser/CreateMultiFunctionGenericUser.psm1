Set-StrictMode -Version Latest

function Invoke-CreateMultiFunctionGenericUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','TargetAdObjectName','TargetDomain','TargetUserAdDisplayname','TargetUserAdEmployeeType','Description','Manager','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        foreach ($row in $rows) {
            & $Context.Services.UserProvisioning.NewUser $Context $row
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-CreateMultiFunctionGenericUser processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-CreateMultiFunctionGenericUser succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-CreateMultiFunctionGenericUser failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-CreateMultiFunctionGenericUser')

Set-StrictMode -Version Latest

function Invoke-DisableGenericUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        foreach ($row in $rows) {
            & $Context.Services.UserProvisioning.DisableUser $Context $row
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-DisableGenericUser processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-DisableGenericUser succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-DisableGenericUser failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-DisableGenericUser')

Set-StrictMode -Version Latest

function Invoke-EnableGenericUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        foreach ($row in $rows) {
            & $Context.Services.UserProvisioning.EnableUser $Context $row
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-EnableGenericUser processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-EnableGenericUser succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-EnableGenericUser failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-EnableGenericUser')

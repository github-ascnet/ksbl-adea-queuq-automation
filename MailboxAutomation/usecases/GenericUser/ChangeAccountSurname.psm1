Set-StrictMode -Version Latest

function Invoke-ChangeAccountSurname {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','GivenName','SurName','NewPrimaryEMailAddress','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        foreach ($row in $rows) {
            & $Context.Services.UserProvisioning.SetSurname $Context $row
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-ChangeAccountSurname processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-ChangeAccountSurname succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-ChangeAccountSurname failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-ChangeAccountSurname')

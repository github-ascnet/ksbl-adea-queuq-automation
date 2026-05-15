Set-StrictMode -Version Latest

function Invoke-RenameUserAccount {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','TargetAdObjectName','NewUserId','GivenName','SurName','NewPrimaryEMailAddress','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        foreach ($row in $rows) {
            & $Context.Services.UserProvisioning.RenameUser $Context $row
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-RenameUserAccount processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-RenameUserAccount succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-RenameUserAccount failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-RenameUserAccount')

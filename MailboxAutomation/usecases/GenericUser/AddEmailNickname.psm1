Set-StrictMode -Version Latest

function Invoke-AddEmailNickname {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','NewPrimaryEMailAddress','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        foreach ($row in $rows) {
            & $Context.Services.UserProvisioning.AddEmailNickname $Context $row
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-AddEmailNickname processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-AddEmailNickname succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-AddEmailNickname failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-AddEmailNickname')

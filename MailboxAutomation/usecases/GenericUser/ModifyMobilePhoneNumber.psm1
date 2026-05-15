Set-StrictMode -Version Latest

function Invoke-ModifyMobilePhoneNumber {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','MobileNumber','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        foreach ($row in $rows) {
            & $Context.Services.UserProvisioning.SetMobilePhoneNumber $Context $row
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-ModifyMobilePhoneNumber processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-ModifyMobilePhoneNumber succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-ModifyMobilePhoneNumber failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-ModifyMobilePhoneNumber')

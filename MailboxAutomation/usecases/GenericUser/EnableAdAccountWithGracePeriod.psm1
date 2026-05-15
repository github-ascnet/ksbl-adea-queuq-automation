Set-StrictMode -Version Latest

function Invoke-EnableAdAccountWithGracePeriod {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','TargetAdObjectName','GracePeriod','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        foreach ($row in $rows) {
            & $Context.Services.UserProvisioning.EnableWithGracePeriod $Context $row
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-EnableAdAccountWithGracePeriod processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-EnableAdAccountWithGracePeriod succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-EnableAdAccountWithGracePeriod failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-EnableAdAccountWithGracePeriod')

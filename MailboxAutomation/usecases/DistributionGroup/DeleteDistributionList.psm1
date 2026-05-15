Set-StrictMode -Version Latest

function Invoke-DeleteDistributionList {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        foreach ($row in $rows) {
            # TODO: Migrate legacy logic here
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-DeleteDistributionList processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-DeleteDistributionList succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-DeleteDistributionList failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-DeleteDistributionList')

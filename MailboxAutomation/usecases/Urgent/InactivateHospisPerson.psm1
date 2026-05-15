Set-StrictMode -Version Latest

function Invoke-InactivateHospisPerson {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','PersId','DisplayName','MigrateUser','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        foreach ($row in $rows) {
            # TODO: Migrate legacy logic here (from Process-UrgentJobs.ps1: Inaktivieren_HospisPersonUrgentUseCase)
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-InactivateHospisPerson processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-InactivateHospisPerson succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-InactivateHospisPerson failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-InactivateHospisPerson')

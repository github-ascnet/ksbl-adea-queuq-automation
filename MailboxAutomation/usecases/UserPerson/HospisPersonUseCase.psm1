Set-StrictMode -Version Latest

function Invoke-HospisPersonUseCase {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','PersId','DisplayName','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        foreach ($row in $rows) {
            # TODO: Add ActionType-specific required field checks from Process-UserPersonJobs.ps1
            # (e.g. RefUserId/RefUserDomain/LocationName/MigrateUser depending on ActionType).
            # AdObjectName must remain optional here (commented in legacy validation).
            # TODO: Migrate legacy logic here (from Process-UserPersonJobs.ps1: HospisPersonUseCase)
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-HospisPersonUseCase processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-HospisPersonUseCase succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-HospisPersonUseCase failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-HospisPersonUseCase')

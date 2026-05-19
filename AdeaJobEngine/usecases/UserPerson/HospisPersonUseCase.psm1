Set-StrictMode -Version Latest

function Assert-HospisPersonActionSpecificFields {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Rows
    )

    foreach ($row in $Rows) {
        $action = [string]$row.ActionType

        switch -Regex ($action) {
            '^(Erstellen|Aktivieren|Standortwechsel|UebertrittM1|UebertrittM2|ÜbertrittM1|ÜbertrittM2)$' {
                Assert-NonEmptyString -Value ([string]$row.RefUserId) -FieldName 'RefUserId'
                Assert-NonEmptyString -Value ([string]$row.RefUserDomain) -FieldName 'RefUserDomain'
            }
        }

        if ($action -match '^(Aktivieren|Standortwechsel)$') {
            Assert-NonEmptyString -Value ([string]$row.MigrateUser) -FieldName 'MigrateUser'
        }

        if ($action -eq 'Standortwechsel') {
            Assert-NonEmptyString -Value ([string]$row.LocationName) -FieldName 'LocationName'
        }
    }
}

function Invoke-HospisPersonUseCase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context
    )

    try {
        $rows = @($Context.Payload)

        # Legacy validation intentionally keeps AdObjectName optional.
        # In current-scripts/Process-UserPersonJobs.ps1 AdObjectName, RefUserId, RefUserDomain and LocationName
        # were partially commented out and are only required for certain ActionType values.
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @(
            'ActionType',
            'PersId',
            'DisplayName',
            'CurrentUserName',
            'CurrentUserDomainName',
            'CurrentUserEMailAddress'
        )

        Assert-HospisPersonActionSpecificFields -Rows $rows

        $results = @()
        $failedResults = @()

        foreach ($row in $rows) {
            Write-LogInfo -Logger $Context.Logger -Message "Processing UserPerson.HospisPersonUseCase action '$($row.ActionType)' for PersId '$($row.PersId)' / '$($row.DisplayName)'."

            $serviceResult = & $Context.Services.HospisPerson.SubmitTransaction $Context $row
            $results += $serviceResult

            if (-not $serviceResult.Success) {
                $failedResults += $serviceResult
                Write-LogWarn -Logger $Context.Logger -Message "UserPerson.HospisPersonUseCase failed for PersId '$($row.PersId)': $($serviceResult.Message)"
            }
            else {
                Write-LogInfo -Logger $Context.Logger -Message "UserPerson.HospisPersonUseCase completed for PersId '$($row.PersId)': $($serviceResult.Message)"
            }
        }

        if ($failedResults.Count -gt 0) {
            return New-JobFailedResult -Message "UserPerson.HospisPersonUseCase failed for $($failedResults.Count) of $($rows.Count) row(s)." -ErrorCode 'HOSPIS_PERSON_TRANSACTION_FAILED' -Output $results
        }

        return New-JobSucceededResult -Message "UserPerson.HospisPersonUseCase processed $($rows.Count) row(s)." -Output $results
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message 'Invoke-HospisPersonUseCase failed.' -Exception $_.Exception
        return New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-HospisPersonUseCase')

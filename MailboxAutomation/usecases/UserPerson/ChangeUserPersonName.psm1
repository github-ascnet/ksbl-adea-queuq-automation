Set-StrictMode -Version Latest

function Invoke-ChangeUserPersonName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('Identity', 'Surname')

        foreach ($row in $rows) {
            & $Context.Services.UserProvisioning.SetSurname $Context $row
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-ChangeUserPersonName processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-ChangeUserPersonName succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-ChangeUserPersonName failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-ChangeUserPersonName')

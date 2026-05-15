Set-StrictMode -Version Latest

function Invoke-ChangeDistributionGroupOwner {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('GroupIdentity', 'OwnerIdentity')

        foreach ($row in $rows) {
            # TODO: Migrate legacy logic here
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-ChangeDistributionGroupOwner processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-ChangeDistributionGroupOwner succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-ChangeDistributionGroupOwner failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-ChangeDistributionGroupOwner')

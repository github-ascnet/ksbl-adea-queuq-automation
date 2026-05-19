Set-StrictMode -Version Latest

function Invoke-UrgentRecipientAttributeChange {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('Identity', 'AttributeName', 'AttributeValue')

        foreach ($row in $rows) {
            # TODO: Migrate legacy logic here
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-UrgentRecipientAttributeChange processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-UrgentRecipientAttributeChange succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-UrgentRecipientAttributeChange failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-UrgentRecipientAttributeChange')

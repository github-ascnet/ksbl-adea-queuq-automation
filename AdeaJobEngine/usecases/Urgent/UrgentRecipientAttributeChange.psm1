Set-StrictMode -Version Latest

function Invoke-UrgentRecipientAttributeChange {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('Identity', 'AttributeName', 'AttributeValue') -AllowEmptyValues

        $results = @()
        foreach ($row in $rows) {
            $result = Set-UrgentRecipientAttribute `
                -Context $Context `
                -Identity ([string]$row.Identity) `
                -AttributeName ([string]$row.AttributeName) `
                -AttributeValue ([string]$row.AttributeValue) `
                -Operation ([string]$row.Operation)

            $results += $result

            if (-not $result.Success) {
                Write-LogWarn -Logger $Context.Logger -Message "Urgent recipient attribute change failed for '$($result.Identity)' ($($result.AttributeName)): $($result.Message)"
            }
        }

        if ($results.Where({ -not $_.Success }).Count -gt 0) {
            $message = "Invoke-UrgentRecipientAttributeChange failed for $($results.Where({ -not $_.Success }).Count) row(s)."
            Write-LogError -Logger $Context.Logger -Message $message
            return New-JobFailedResult -Message $message -ErrorCode 'URGENT_RECIPIENT_ATTRIBUTE_CHANGE_FAILED' -Output $results
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-UrgentRecipientAttributeChange processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-UrgentRecipientAttributeChange succeeded." -Output $results
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-UrgentRecipientAttributeChange failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-UrgentRecipientAttributeChange')

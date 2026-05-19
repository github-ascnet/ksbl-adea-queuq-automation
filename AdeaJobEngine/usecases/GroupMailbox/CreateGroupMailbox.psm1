Set-StrictMode -Version Latest

function Invoke-CreateGroupMailbox {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','DisplayName','FirstName','LastName','PrimarySmtpAddress','NewPrimaryEMailAddress','AdObjectName','OrgUnit','HideInAb','Manager','FullAccessMembers','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        $results = @()
        $failedResults = @()

        foreach ($row in $rows) {
            Write-LogInfo -Logger $Context.Logger -Message "Processing GroupMailbox.Create for '$($row.DisplayName)' / '$($row.PrimarySmtpAddress)'."

            $serviceResult = & $Context.Services.GroupMailbox.Create $Context $row
            $results += $serviceResult

            if (-not $serviceResult.Success) {
                $failedResults += $serviceResult
                Write-LogWarn -Logger $Context.Logger -Message "GroupMailbox.Create failed for '$($row.DisplayName)': $($serviceResult.Message)"
            }
            else {
                Write-LogInfo -Logger $Context.Logger -Message "GroupMailbox.Create completed for '$($row.DisplayName)': $($serviceResult.Message)"
            }
        }

        if ($failedResults.Count -gt 0) {
            return New-JobFailedResult -Message "GroupMailbox.Create failed for $($failedResults.Count) of $($rows.Count) row(s)." -ErrorCode 'GROUP_MAILBOX_CREATE_FAILED' -Output $results
        }

        return New-JobSucceededResult -Message "GroupMailbox.Create processed $($rows.Count) row(s)." -Output $results
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message 'Invoke-CreateGroupMailbox failed.' -Exception $_.Exception
        return New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-CreateGroupMailbox')

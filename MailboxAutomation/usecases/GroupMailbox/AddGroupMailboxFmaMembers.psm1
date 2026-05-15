Set-StrictMode -Version Latest

function Invoke-AddGroupMailboxFmaMembers {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','FullAccessMembers','EnableSendAs','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        $results = @()
        $failedResults = @()

        foreach ($row in $rows) {
            Write-LogInfo -Logger $Context.Logger -Message "Processing GroupMailbox.AddFmaMembers for '$($row.AdObjectName)'."

            $serviceResult = & $Context.Services.GroupMailbox.AddFmaMembers $Context $row
            $results += $serviceResult

            if (-not $serviceResult.Success) {
                $failedResults += $serviceResult
                Write-LogWarn -Logger $Context.Logger -Message "GroupMailbox.AddFmaMembers failed for '$($row.AdObjectName)': $($serviceResult.Message)"
            }
            else {
                Write-LogInfo -Logger $Context.Logger -Message "GroupMailbox.AddFmaMembers completed for '$($row.AdObjectName)': $($serviceResult.Message)"
            }
        }

        if ($failedResults.Count -gt 0) {
            return New-JobFailedResult -Message "GroupMailbox.AddFmaMembers failed for $($failedResults.Count) of $($rows.Count) row(s)." -ErrorCode 'GROUP_MAILBOX_FMA_MEMBERS_FAILED' -Output $results
        }

        return New-JobSucceededResult -Message "GroupMailbox.AddFmaMembers processed $($rows.Count) row(s)." -Output $results
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message 'Invoke-AddGroupMailboxFmaMembers failed.' -Exception $_.Exception
        return New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-AddGroupMailboxFmaMembers')

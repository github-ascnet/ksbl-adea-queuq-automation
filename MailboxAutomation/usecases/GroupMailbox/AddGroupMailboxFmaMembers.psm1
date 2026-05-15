Set-StrictMode -Version Latest

function Invoke-AddGroupMailboxFmaMembers {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','FullAccessMembers','EnableSendAs','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        foreach ($row in $rows) {
            # TODO: Migrate legacy logic here
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-AddGroupMailboxFmaMembers processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-AddGroupMailboxFmaMembers succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-AddGroupMailboxFmaMembers failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-AddGroupMailboxFmaMembers')

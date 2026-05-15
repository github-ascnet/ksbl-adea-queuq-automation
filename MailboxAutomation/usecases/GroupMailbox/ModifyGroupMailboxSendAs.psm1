Set-StrictMode -Version Latest

function Invoke-ModifyGroupMailboxSendAs {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('MailboxIdentity', 'Trustee', 'Operation')

        foreach ($row in $rows) {
            if ($row.Operation -eq "Remove") { & $Context.Services.MailboxPermission.RemoveSendAs $Context $row } else { & $Context.Services.MailboxPermission.AddSendAs $Context $row }
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-ModifyGroupMailboxSendAs processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-ModifyGroupMailboxSendAs succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-ModifyGroupMailboxSendAs failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-ModifyGroupMailboxSendAs')

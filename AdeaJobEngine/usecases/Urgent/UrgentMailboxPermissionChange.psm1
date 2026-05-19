Set-StrictMode -Version Latest

function Invoke-UrgentMailboxPermissionChange {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('MailboxIdentity', 'Trustee', 'PermissionType', 'Operation')

        foreach ($row in $rows) {
            if ($row.PermissionType -eq "SendAs") { if ($row.Operation -eq "Remove") { & $Context.Services.MailboxPermission.RemoveSendAs $Context $row } else { & $Context.Services.MailboxPermission.AddSendAs $Context $row } } else { if ($row.Operation -eq "Remove") { & $Context.Services.MailboxPermission.RemoveFullAccess $Context $row } else { & $Context.Services.MailboxPermission.AddFullAccess $Context $row } }
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-UrgentMailboxPermissionChange processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-UrgentMailboxPermissionChange succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-UrgentMailboxPermissionChange failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-UrgentMailboxPermissionChange')

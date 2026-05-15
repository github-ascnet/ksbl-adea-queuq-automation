Set-StrictMode -Version Latest

function Invoke-ModifyGroupMailboxFullAccess {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('MailboxIdentity', 'Trustee', 'Operation')

        foreach ($row in $rows) {
            if ($row.Operation -eq "Remove") { & $Context.Services.MailboxPermission.RemoveFullAccess $Context $row } else { & $Context.Services.MailboxPermission.AddFullAccess $Context $row }
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-ModifyGroupMailboxFullAccess processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-ModifyGroupMailboxFullAccess succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-ModifyGroupMailboxFullAccess failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-ModifyGroupMailboxFullAccess')

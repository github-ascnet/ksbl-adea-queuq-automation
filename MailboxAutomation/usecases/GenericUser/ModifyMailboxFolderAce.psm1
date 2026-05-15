Set-StrictMode -Version Latest

function Invoke-ModifyMailboxFolderAce {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','MailboxFolderName','DelegatedAdObjectName','AclActionType','AclEntry','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        foreach ($row in $rows) {
            & $Context.Services.UserProvisioning.SetMailboxFolderAce $Context $row
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-ModifyMailboxFolderAce processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-ModifyMailboxFolderAce succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-ModifyMailboxFolderAce failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-ModifyMailboxFolderAce')

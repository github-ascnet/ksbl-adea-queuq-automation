Set-StrictMode -Version Latest

function Invoke-ChangeManagerGroupMailbox {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','AdObjectName','ManagerAdObjectName','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        foreach ($row in $rows) {
            # TODO: Migrate legacy logic here
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-ChangeManagerGroupMailbox processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-ChangeManagerGroupMailbox succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-ChangeManagerGroupMailbox failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-ChangeManagerGroupMailbox')

Set-StrictMode -Version Latest

function Invoke-CreateGroupMailbox {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','DisplayName','FirstName','LastName','PrimarySmtpAddress','NewPrimaryEMailAddress','AdObjectName','OrgUnit','HideInAb','Manager','FullAccessMembers','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        foreach ($row in $rows) {
            # TODO: Migrate legacy logic here
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-CreateGroupMailbox processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-CreateGroupMailbox succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-CreateGroupMailbox failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-CreateGroupMailbox')

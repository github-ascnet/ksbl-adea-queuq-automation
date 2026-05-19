Set-StrictMode -Version Latest

function Invoke-AddUserPersonEmailNickname {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('Identity', 'EmailNickname')

        foreach ($row in $rows) {
            & $Context.Services.UserProvisioning.AddEmailNickname $Context $row
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-AddUserPersonEmailNickname processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-AddUserPersonEmailNickname succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-AddUserPersonEmailNickname failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-AddUserPersonEmailNickname')

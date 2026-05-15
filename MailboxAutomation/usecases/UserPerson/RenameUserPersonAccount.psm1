Set-StrictMode -Version Latest

function Invoke-RenameUserPersonAccount {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('Identity', 'NewName')

        foreach ($row in $rows) {
            & $Context.Services.UserProvisioning.RenameUser $Context $row
        }

        Write-LogInfo -Logger $Context.Logger -Message "Invoke-RenameUserPersonAccount processed $($rows.Count) row(s)."
        New-JobSucceededResult -Message "Invoke-RenameUserPersonAccount succeeded."
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-RenameUserPersonAccount failed." -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-RenameUserPersonAccount')

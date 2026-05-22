Set-StrictMode -Version Latest

function Get-MailboxPermissionBackfeedOnPremRawRows {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    @()
}

function Get-MailboxPermissionBackfeedExchangeOnlineRawRows {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    @()
}

function Read-MailboxPermissionBackfeedSources {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$BackfeedContext)

    $rows = @()

    $rows += @(
        Get-MailboxPermissionBackfeedOnPremRawRows -Context $BackfeedContext
    )

    $rows += @(
        Get-MailboxPermissionBackfeedExchangeOnlineRawRows -Context $BackfeedContext
    )

    @($rows | Where-Object { $null -ne $_ })
}

Export-ModuleMember -Function @(
    'Read-MailboxPermissionBackfeedSources',
    'Get-MailboxPermissionBackfeedOnPremRawRows',
    'Get-MailboxPermissionBackfeedExchangeOnlineRawRows'
)
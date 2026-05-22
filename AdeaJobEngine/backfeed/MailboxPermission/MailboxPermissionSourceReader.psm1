Set-StrictMode -Version Latest

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$engineRoot = Split-Path -Parent (Split-Path -Parent $moduleRoot)
Import-Module -Name (Join-Path -Path $engineRoot -ChildPath 'infrastructure\ExchangeOnPremGateway.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path -Path $engineRoot -ChildPath 'infrastructure\ExchangeOnlineGateway.psm1') -Force -DisableNameChecking

function Get-MailboxPermissionConfiguredSources {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$BackfeedContext)

    $configuredSources = @()
    if ($null -ne $BackfeedContext.Config -and $null -ne $BackfeedContext.Config.BackfeedTypes -and $null -ne $BackfeedContext.Config.BackfeedTypes.MailboxPermission) {
        $configuredSources = @($BackfeedContext.Config.BackfeedTypes.MailboxPermission.Sources)
    }

    if (@($configuredSources).Count -eq 0) {
        return @('ExchangeOnPrem', 'ExchangeOnline')
    }

    $resolved = foreach ($source in @($configuredSources)) {
        switch -Regex ([string]$source) {
            '^(ExchangeOnPrem|OnPrem)$' { 'ExchangeOnPrem'; continue }
            '^(ExchangeOnline|EXO)$' { 'ExchangeOnline'; continue }
            default { continue }
        }
    }

    $distinct = @($resolved | Select-Object -Unique)
    if ($distinct.Count -eq 0) {
        return @('ExchangeOnPrem', 'ExchangeOnline')
    }

    $distinct
}

function ConvertTo-MailboxPermissionRawPermissions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowEmptyCollection()][object[]]$Records,
        [Parameter(Mandatory = $true)][string]$SourceSystem,
        [Parameter(Mandatory = $true)][string]$PermissionType
    )

    if (@($Records).Count -eq 0) {
        return @()
    }

    $rows = foreach ($record in @($Records)) {
        if ($null -eq $record) { continue }

        [pscustomobject]@{
            SourceSystem                         = $SourceSystem
            PermissionType                       = $PermissionType
            MailboxIdentity                      = [string]$record.MailboxIdentity
            MailboxName                          = [string]$record.MailboxName
            MailboxDistinguishedName             = [string]$record.MailboxDistinguishedName
            MailboxGuid                          = [string]$record.MailboxGuid
            MailboxHiddenFromAddressListsEnabled = $record.MailboxHiddenFromAddressListsEnabled
            TrusteeIdentity                      = [string]$record.TrusteeIdentity
            TrusteeName                          = [string]$record.TrusteeName
            TrusteeDomain                        = [string]$record.TrusteeDomain
            TrusteeDistinguishedName             = [string]$record.TrusteeDistinguishedName
            TrusteeSid                           = [string]$record.TrusteeSid
            TrusteeObjectClass                   = [string]$record.TrusteeObjectClass
            AccessRights                         = $record.AccessRights
            IsInherited                          = $record.IsInherited
            Deny                                 = $record.Deny
        }
    }

    @($rows)
}

function Get-OnPremMailboxFullAccessPermissionRecords {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $mailboxes = @(Invoke-OnPremMailboxPermissionBackfeedMailboxesGatewayRead -Context $Context)
    $records = @()

    foreach ($mailbox in $mailboxes) {
        if ($null -eq $mailbox) { continue }
        $mailboxIdentity = [string]$mailbox.Identity
        if ([string]::IsNullOrWhiteSpace($mailboxIdentity)) { continue }

        $records += @(Invoke-OnPremMailboxFullAccessGatewayRead -Identity $mailboxIdentity -Context $Context)
    }

    @($records)
}

function Get-OnPremMailboxSendAsPermissionRecords {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $mailboxes = @(Invoke-OnPremMailboxPermissionBackfeedMailboxesGatewayRead -Context $Context)
    $records = @()

    foreach ($mailbox in $mailboxes) {
        if ($null -eq $mailbox) { continue }
        $mailboxIdentity = [string]$mailbox.Identity
        if ([string]::IsNullOrWhiteSpace($mailboxIdentity)) { continue }

        $records += @(
            Invoke-OnPremMailboxSendAsGatewayRead -Identity $mailboxIdentity -DistinguishedName ([string]$mailbox.DistinguishedName) -Context $Context
        )
    }

    @($records)
}

function Invoke-OnPremMailboxPermissionBackfeedMailboxesGatewayRead {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    Get-OnPremMailboxPermissionBackfeedMailboxes -Context $Context
}

function Invoke-OnPremMailboxFullAccessGatewayRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][object]$Context
    )

    Get-OnPremMailboxFullAccessPermissionsSafe -Identity $Identity -Context $Context
}

function Invoke-OnPremMailboxSendAsGatewayRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [string]$DistinguishedName,
        [Parameter(Mandatory = $true)][object]$Context
    )

    Get-OnPremMailboxSendAsPermissionsSafe -Identity $Identity -DistinguishedName $DistinguishedName -Context $Context
}

function Get-ExchangeOnlineMailboxFullAccessPermissionRecords {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $mailboxes = @(Invoke-ExchangeOnlineMailboxPermissionBackfeedMailboxesGatewayRead -Context $Context)
    $records = @()

    foreach ($mailbox in $mailboxes) {
        if ($null -eq $mailbox) { continue }
        $mailboxIdentity = [string]$mailbox.Identity
        if ([string]::IsNullOrWhiteSpace($mailboxIdentity)) { continue }

        $records += @(Invoke-ExchangeOnlineMailboxFullAccessGatewayRead -Identity $mailboxIdentity -Context $Context)
    }

    @($records)
}

function Get-ExchangeOnlineMailboxSendAsPermissionRecords {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $mailboxes = @(Invoke-ExchangeOnlineMailboxPermissionBackfeedMailboxesGatewayRead -Context $Context)
    $records = @()

    foreach ($mailbox in $mailboxes) {
        if ($null -eq $mailbox) { continue }
        $mailboxIdentity = [string]$mailbox.Identity
        if ([string]::IsNullOrWhiteSpace($mailboxIdentity)) { continue }

        $records += @(Invoke-ExchangeOnlineMailboxSendAsGatewayRead -Identity $mailboxIdentity -Context $Context)
    }

    @($records)
}

function Invoke-ExchangeOnlineMailboxPermissionBackfeedMailboxesGatewayRead {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    Get-ExchangeOnlineMailboxPermissionBackfeedMailboxes -Context $Context
}

function Invoke-ExchangeOnlineMailboxFullAccessGatewayRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][object]$Context
    )

    Get-ExchangeOnlineMailboxFullAccessPermissionsSafe -Identity $Identity -Context $Context
}

function Invoke-ExchangeOnlineMailboxSendAsGatewayRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][object]$Context
    )

    Get-ExchangeOnlineMailboxSendAsPermissionsSafe -Identity $Identity -Context $Context
}

function Read-OnPremMailboxFullAccessPermissions {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$BackfeedContext)

    $records = @(Get-OnPremMailboxFullAccessPermissionRecords -Context $BackfeedContext)
    ConvertTo-MailboxPermissionRawPermissions -Records $records -SourceSystem 'OnPrem' -PermissionType 'FullAccess'
}

function Read-OnPremMailboxSendAsPermissions {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$BackfeedContext)

    $records = @(Get-OnPremMailboxSendAsPermissionRecords -Context $BackfeedContext)
    ConvertTo-MailboxPermissionRawPermissions -Records $records -SourceSystem 'OnPrem' -PermissionType 'SendAs'
}

function Read-ExchangeOnlineMailboxFullAccessPermissions {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$BackfeedContext)

    $records = @(Get-ExchangeOnlineMailboxFullAccessPermissionRecords -Context $BackfeedContext)
    ConvertTo-MailboxPermissionRawPermissions -Records $records -SourceSystem 'ExchangeOnline' -PermissionType 'FullAccess'
}

function Read-ExchangeOnlineMailboxSendAsPermissions {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$BackfeedContext)

    $records = @(Get-ExchangeOnlineMailboxSendAsPermissionRecords -Context $BackfeedContext)
    ConvertTo-MailboxPermissionRawPermissions -Records $records -SourceSystem 'ExchangeOnline' -PermissionType 'SendAs'
}

function Get-MailboxPermissionBackfeedOnPremRawRows {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $rows = @()
    $rows += @(Read-OnPremMailboxFullAccessPermissions -BackfeedContext $Context)
    $rows += @(Read-OnPremMailboxSendAsPermissions -BackfeedContext $Context)

    @($rows)
}

function Get-MailboxPermissionBackfeedExchangeOnlineRawRows {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $rows = @()
    $rows += @(Read-ExchangeOnlineMailboxFullAccessPermissions -BackfeedContext $Context)
    $rows += @(Read-ExchangeOnlineMailboxSendAsPermissions -BackfeedContext $Context)

    @($rows)
}

function Read-MailboxPermissionBackfeedSources {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$BackfeedContext)

    $rows = @()

    $sources = @(Get-MailboxPermissionConfiguredSources -BackfeedContext $BackfeedContext)

    if ($sources -contains 'ExchangeOnPrem') {
        $rows += @(
            Get-MailboxPermissionBackfeedOnPremRawRows -Context $BackfeedContext
        )
    }

    if ($sources -contains 'ExchangeOnline') {
        $rows += @(
            Get-MailboxPermissionBackfeedExchangeOnlineRawRows -Context $BackfeedContext
        )
    }

    @($rows | Where-Object { $null -ne $_ })
}

Export-ModuleMember -Function @(
    'Read-MailboxPermissionBackfeedSources',
    'Get-MailboxPermissionBackfeedOnPremRawRows',
    'Get-MailboxPermissionBackfeedExchangeOnlineRawRows'
)
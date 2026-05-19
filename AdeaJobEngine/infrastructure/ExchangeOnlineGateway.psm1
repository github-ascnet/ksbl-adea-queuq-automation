Set-StrictMode -Version Latest

function Assert-ExchangeOnlineEnabled {
    param([Parameter(Mandatory = $true)][hashtable]$Config)

    if (-not $Config.ExchangeOnline.Enabled) {
        throw 'Exchange Online is disabled by configuration. Set ExchangeOnline.Enabled=true to use EXO operations.'
    }
}

function Connect-ExchangeOnlineAutomation {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Config)

    Assert-ExchangeOnlineEnabled -Config $Config

    if (-not (Get-Command -Name Connect-ExchangeOnline -ErrorAction SilentlyContinue)) {
        throw 'Connect-ExchangeOnline cmdlet is not available. Install ExchangeOnlineManagement module.'
    }

    $params = @{
        AppId                = $Config.ExchangeOnline.AppId
        CertificateThumbprint = $Config.ExchangeOnline.CertificateThumbprint
        Organization         = $Config.ExchangeOnline.Organization
        ShowBanner           = $false
    }

    Connect-ExchangeOnline @params -ErrorAction Stop
}

function Get-ExoMailboxSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Identity, [Parameter(Mandatory = $true)][hashtable]$Config)

    Assert-ExchangeOnlineEnabled -Config $Config
    if (-not (Get-Command -Name Get-EXOMailbox -ErrorAction SilentlyContinue)) { throw 'Get-EXOMailbox cmdlet unavailable.' }
    Get-EXOMailbox -Identity $Identity -ErrorAction Stop
}

function Set-ExoMailboxSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [Parameter(Mandatory = $true)][hashtable]$Config, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Set-EXOMailbox'; Parameters = $Parameters } }
    Assert-ExchangeOnlineEnabled -Config $Config
    if (-not (Get-Command -Name Set-Mailbox -ErrorAction SilentlyContinue)) { throw 'Set-Mailbox cmdlet unavailable for EXO session.' }
    Set-Mailbox @Parameters -ErrorAction Stop
}

function Get-ExoRecipientSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Identity, [Parameter(Mandatory = $true)][hashtable]$Config)

    Assert-ExchangeOnlineEnabled -Config $Config
    if (-not (Get-Command -Name Get-EXORecipient -ErrorAction SilentlyContinue)) { throw 'Get-EXORecipient cmdlet unavailable.' }
    Get-EXORecipient -Identity $Identity -ErrorAction Stop
}

function Add-ExoMailboxPermissionSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [Parameter(Mandatory = $true)][hashtable]$Config, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Add-MailboxPermission'; Parameters = $Parameters } }
    Assert-ExchangeOnlineEnabled -Config $Config
    Add-MailboxPermission @Parameters -ErrorAction Stop
}

function Remove-ExoMailboxPermissionSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [Parameter(Mandatory = $true)][hashtable]$Config, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Remove-MailboxPermission'; Parameters = $Parameters } }
    Assert-ExchangeOnlineEnabled -Config $Config
    Remove-MailboxPermission @Parameters -ErrorAction Stop
}

function Add-ExoSendAsPermissionSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [Parameter(Mandatory = $true)][hashtable]$Config, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Add-RecipientPermission'; Parameters = $Parameters } }
    Assert-ExchangeOnlineEnabled -Config $Config
    Add-RecipientPermission @Parameters -ErrorAction Stop
}

function Remove-ExoSendAsPermissionSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [Parameter(Mandatory = $true)][hashtable]$Config, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Remove-RecipientPermission'; Parameters = $Parameters } }
    Assert-ExchangeOnlineEnabled -Config $Config
    Remove-RecipientPermission @Parameters -ErrorAction Stop
}

function Set-ExoMailboxManagerSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][string]$Manager,
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{
            Simulated = $true
            Action    = 'Set-Mailbox'
            Identity  = $Identity
            Manager   = $Manager
            Target    = 'ExchangeOnline'
        }
    }
    Assert-ExchangeOnlineEnabled -Config $Config
    if (-not (Get-Command -Name Set-Mailbox -ErrorAction SilentlyContinue)) { throw 'Set-Mailbox cmdlet unavailable for EXO session.' }
    Set-Mailbox -Identity $Identity -GrantSendOnBehalfTo @{ Add = $Manager } -ErrorAction Stop
}

Export-ModuleMember -Function @(
    'Connect-ExchangeOnlineAutomation',
    'Get-ExoMailboxSafe',
    'Set-ExoMailboxSafe',
    'Get-ExoRecipientSafe',
    'Add-ExoMailboxPermissionSafe',
    'Remove-ExoMailboxPermissionSafe',
    'Add-ExoSendAsPermissionSafe',
    'Remove-ExoSendAsPermissionSafe',
    'Set-ExoMailboxManagerSafe'
)

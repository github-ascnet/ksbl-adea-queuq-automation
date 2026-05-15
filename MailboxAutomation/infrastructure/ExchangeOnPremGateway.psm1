Set-StrictMode -Version Latest

function Assert-OnPremCmdlet {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required Exchange On-Prem cmdlet '$Name' is not available in current session."
    }
}

function Get-OnPremMailboxSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Identity)

    Assert-OnPremCmdlet -Name 'Get-Mailbox'
    Get-Mailbox -Identity $Identity -ErrorAction Stop
}

function Set-OnPremMailboxSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Set-Mailbox'; Parameters = $Parameters } }
    Assert-OnPremCmdlet -Name 'Set-Mailbox'
    Set-Mailbox @Parameters -ErrorAction Stop
}

function Get-OnPremRecipientSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Identity)

    Assert-OnPremCmdlet -Name 'Get-Recipient'
    Get-Recipient -Identity $Identity -ErrorAction Stop
}

function Add-OnPremMailboxPermissionSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Add-MailboxPermission'; Parameters = $Parameters } }
    Assert-OnPremCmdlet -Name 'Add-MailboxPermission'
    Add-MailboxPermission @Parameters -ErrorAction Stop
}

function Remove-OnPremMailboxPermissionSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Remove-MailboxPermission'; Parameters = $Parameters } }
    Assert-OnPremCmdlet -Name 'Remove-MailboxPermission'
    Remove-MailboxPermission @Parameters -ErrorAction Stop
}

function Add-OnPremSendAsPermissionSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Add-RecipientPermission'; Parameters = $Parameters } }
    Assert-OnPremCmdlet -Name 'Add-RecipientPermission'
    Add-RecipientPermission @Parameters -ErrorAction Stop
}

function Remove-OnPremSendAsPermissionSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Remove-RecipientPermission'; Parameters = $Parameters } }
    Assert-OnPremCmdlet -Name 'Remove-RecipientPermission'
    Remove-RecipientPermission @Parameters -ErrorAction Stop
}

Export-ModuleMember -Function @(
    'Get-OnPremMailboxSafe',
    'Set-OnPremMailboxSafe',
    'Get-OnPremRecipientSafe',
    'Add-OnPremMailboxPermissionSafe',
    'Remove-OnPremMailboxPermissionSafe',
    'Add-OnPremSendAsPermissionSafe',
    'Remove-OnPremSendAsPermissionSafe'
)

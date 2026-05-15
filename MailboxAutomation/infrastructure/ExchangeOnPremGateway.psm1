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


function Get-OnPremDistributionGroupSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Identity)

    Assert-OnPremCmdlet -Name 'Get-DistributionGroup'
    Get-DistributionGroup -Identity $Identity -ErrorAction Stop
}

function Set-OnPremDistributionGroupSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Set-DistributionGroup'; Parameters = $Parameters } }
    Assert-OnPremCmdlet -Name 'Set-DistributionGroup'
    Set-DistributionGroup @Parameters -ErrorAction Stop
}

function Get-OnPremMailboxPermissionSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Identity)

    Assert-OnPremCmdlet -Name 'Get-MailboxPermission'
    Get-MailboxPermission -Identity $Identity -ErrorAction Stop
}

function Get-OnPremAdPermissionSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Identity)

    Assert-OnPremCmdlet -Name 'Get-ADPermission'
    Get-ADPermission -Identity $Identity -ErrorAction Stop
}

function Add-OnPremAdPermissionSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Add-ADPermission'; Parameters = $Parameters } }
    Assert-OnPremCmdlet -Name 'Add-ADPermission'
    Add-ADPermission @Parameters -ErrorAction Stop
}

function Remove-OnPremAdPermissionSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Remove-ADPermission'; Parameters = $Parameters } }
    Assert-OnPremCmdlet -Name 'Remove-ADPermission'
    Remove-ADPermission @Parameters -ErrorAction Stop
}



function Enable-OnPremMailboxSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Enable-Mailbox'; Parameters = $Parameters } }
    Assert-OnPremCmdlet -Name 'Enable-Mailbox'
    Enable-Mailbox @Parameters -ErrorAction Stop
}

function Set-OnPremCASMailboxSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Set-CASMailbox'; Parameters = $Parameters } }
    Assert-OnPremCmdlet -Name 'Set-CASMailbox'
    Set-CASMailbox @Parameters -ErrorAction Stop
}

function New-OnPremMailboxSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'New-Mailbox'; Parameters = $Parameters } }
    Assert-OnPremCmdlet -Name 'New-Mailbox'
    New-Mailbox @Parameters -ErrorAction Stop
}

function Set-OnPremMailboxJunkEmailConfigurationSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Set-MailboxJunkEmailConfiguration'; Parameters = $Parameters } }
    Assert-OnPremCmdlet -Name 'Set-MailboxJunkEmailConfiguration'
    Set-MailboxJunkEmailConfiguration @Parameters -ErrorAction Stop
}



function Set-OnPremMailboxAutoReplyConfigurationSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Set-MailboxAutoReplyConfiguration'; Parameters = $Parameters } }
    Assert-OnPremCmdlet -Name 'Set-MailboxAutoReplyConfiguration'
    Set-MailboxAutoReplyConfiguration @Parameters -ErrorAction Stop
}


Export-ModuleMember -Function @(
    'Get-OnPremMailboxSafe',
    'New-OnPremMailboxSafe',
    'Set-OnPremCASMailboxSafe',
    'Enable-OnPremMailboxSafe',
    'Set-OnPremMailboxJunkEmailConfigurationSafe',
    'Set-OnPremMailboxAutoReplyConfigurationSafe',
    'Set-OnPremMailboxSafe',
    'Get-OnPremRecipientSafe',
    'Add-OnPremMailboxPermissionSafe',
    'Remove-OnPremMailboxPermissionSafe',
    'Add-OnPremSendAsPermissionSafe',
    'Remove-OnPremSendAsPermissionSafe',
    'Get-OnPremDistributionGroupSafe',
    'Set-OnPremDistributionGroupSafe',
    'Get-OnPremMailboxPermissionSafe',
    'Get-OnPremAdPermissionSafe',
    'Add-OnPremAdPermissionSafe',
    'Remove-OnPremAdPermissionSafe'
)

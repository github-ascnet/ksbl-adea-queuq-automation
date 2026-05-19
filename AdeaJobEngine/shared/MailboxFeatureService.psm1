Set-StrictMode -Version Latest

function Set-MailboxFeatures {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data,
        [Parameter(Mandatory = $false)][psobject]$Resolution = $null
    )

    # TODO: Migrate additional legacy mailbox feature logic here.
    $identity = $Data.MailboxIdentity
    $recipientType = if ($Resolution) { [string]$Resolution.RecipientTypeDetails } else { '' }

    if ($recipientType -in @('RemoteUserMailbox', 'RemoteSharedMailbox')) {
        Set-OnPremRemoteMailboxSafe -Parameters @{ Identity = $identity; HiddenFromAddressListsEnabled = $false } -WhatIfMode:$Context.WhatIfMode
    }
    else {
        Set-OnPremMailboxSafe -Parameters @{ Identity = $identity; HiddenFromAddressListsEnabled = $false } -WhatIfMode:$Context.WhatIfMode
    }
}

function Disable-MailboxFeatures {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data,
        [Parameter(Mandatory = $false)][psobject]$Resolution = $null
    )

    # TODO: Migrate additional legacy mailbox feature logic here.
    $identity = $Data.MailboxIdentity
    $recipientType = if ($Resolution) { [string]$Resolution.RecipientTypeDetails } else { '' }

    if ($recipientType -in @('RemoteUserMailbox', 'RemoteSharedMailbox')) {
        Set-OnPremRemoteMailboxSafe -Parameters @{ Identity = $identity; HiddenFromAddressListsEnabled = $true } -WhatIfMode:$Context.WhatIfMode
    }
    else {
        Set-OnPremMailboxSafe -Parameters @{ Identity = $identity; HiddenFromAddressListsEnabled = $true } -WhatIfMode:$Context.WhatIfMode
    }
}

function Set-MailboxVisibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$MailboxName,
        [Parameter(Mandatory = $true)][ValidateSet('Hide','Unhide')][string]$Visibility,
        [bool]$WhatIfMode = $true,
        [Parameter(Mandatory = $false)][psobject]$Resolution = $null
    )

    $hidden = $Visibility -eq 'Hide'
    $recipientType = if ($Resolution) { [string]$Resolution.RecipientTypeDetails } else { '' }

    # RemoteUserMailbox / RemoteSharedMailbox: HideFromAddressLists is a synchronized attribute.
    # Set it via Set-RemoteMailbox On-Prem (synced to EXO via Entra Connect). No EXO needed.
    if ($recipientType -in @('RemoteUserMailbox', 'RemoteSharedMailbox')) {
        Set-OnPremRemoteMailboxSafe -Parameters @{
            Identity                    = $MailboxName
            HiddenFromAddressListsEnabled = $hidden
        } -WhatIfMode:$WhatIfMode
    }
    else {
        Set-OnPremMailboxSafe -Parameters @{
            Identity                    = $MailboxName
            HiddenFromAddressListsEnabled = $hidden
        } -WhatIfMode:$WhatIfMode
    }
}

Export-ModuleMember -Function @('Set-MailboxFeatures','Disable-MailboxFeatures','Set-MailboxVisibility')


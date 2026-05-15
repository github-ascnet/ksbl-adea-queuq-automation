Set-StrictMode -Version Latest

function Set-MailboxFeatures {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    # TODO: Migrate additional legacy mailbox feature logic here.
    Set-OnPremMailboxSafe -Parameters @{ Identity = $Data.MailboxIdentity; HiddenFromAddressListsEnabled = $false } -WhatIfMode:$Context.WhatIfMode
}

function Disable-MailboxFeatures {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    # TODO: Migrate additional legacy mailbox feature logic here.
    Set-OnPremMailboxSafe -Parameters @{ Identity = $Data.MailboxIdentity; HiddenFromAddressListsEnabled = $true } -WhatIfMode:$Context.WhatIfMode
}

function Set-MailboxVisibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$MailboxName,
        [Parameter(Mandatory = $true)][ValidateSet('Hide','Unhide')][string]$Visibility,
        [bool]$WhatIfMode = $true
    )

    $hidden = $Visibility -eq 'Hide'
    Set-OnPremMailboxSafe -Parameters @{
        Identity = $MailboxName
        HiddenFromAddressListsEnabled = $hidden
    } -WhatIfMode:$WhatIfMode
}

Export-ModuleMember -Function @('Set-MailboxFeatures','Disable-MailboxFeatures','Set-MailboxVisibility')

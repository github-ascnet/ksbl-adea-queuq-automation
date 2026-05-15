Set-StrictMode -Version Latest

function Set-MailboxFeatures {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    # TODO: Migrate legacy logic here
    Set-OnPremMailboxSafe -Parameters @{ Identity = $Data.MailboxIdentity; HiddenFromAddressListsEnabled = $false } -WhatIfMode:$Context.WhatIfMode
}

function Disable-MailboxFeatures {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    # TODO: Migrate legacy logic here
    Set-OnPremMailboxSafe -Parameters @{ Identity = $Data.MailboxIdentity; HiddenFromAddressListsEnabled = $true } -WhatIfMode:$Context.WhatIfMode
}

Export-ModuleMember -Function @('Set-MailboxFeatures','Disable-MailboxFeatures')

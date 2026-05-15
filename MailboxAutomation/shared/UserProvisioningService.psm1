Set-StrictMode -Version Latest

function New-GenericUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $sam = Get-NextAvailableAccountName -BaseName (New-AccountNameCandidate -GivenName $Data.GivenName -Surname $Data.Surname)
    $params = @{ Name = "$($Data.GivenName) $($Data.Surname)"; SamAccountName = $sam; Enabled = $true }
    New-AdUserSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode
}

function Enable-GenericUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    Enable-AdAccountSafe -Identity $Data.Identity -WhatIfMode:$Context.WhatIfMode
}

function Disable-GenericUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    Disable-AdAccountSafe -Identity $Data.Identity -WhatIfMode:$Context.WhatIfMode
}

function Rename-GenericUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $params = @{ Identity = $Data.Identity; NewName = $Data.NewName }
    Rename-AdObjectSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode
}

function Set-GenericUserSurname {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $params = @{ Identity = $Data.Identity; Surname = $Data.Surname }
    Set-AdUserSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode
}

function Add-GenericUserEmailNickname {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    # TODO: Migrate legacy logic here
    $params = @{ Identity = $Data.Identity; Add = @{ proxyAddresses = "smtp:$($Data.EmailNickname)" } }
    Set-AdUserSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode
}

function Enable-GenericUserWithGracePeriod {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    # TODO: Migrate legacy logic here
    Enable-AdAccountSafe -Identity $Data.Identity -WhatIfMode:$Context.WhatIfMode
}

function Set-GenericUserMobilePhoneNumber {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $params = @{ Identity = $Data.Identity; MobilePhone = $Data.MobilePhone }
    Set-AdUserSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode
}

function Set-GenericUserMailboxFolderAce {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    # TODO: Migrate legacy logic here
    Add-MailboxFullAccess -Context $Context -Data ([pscustomobject]@{ MailboxIdentity = $Data.MailboxIdentity; Trustee = $Data.Trustee })
}

Export-ModuleMember -Function @(
    'New-GenericUser',
    'Enable-GenericUser',
    'Disable-GenericUser',
    'Rename-GenericUser',
    'Set-GenericUserSurname',
    'Add-GenericUserEmailNickname',
    'Enable-GenericUserWithGracePeriod',
    'Set-GenericUserMobilePhoneNumber',
    'Set-GenericUserMailboxFolderAce'
)

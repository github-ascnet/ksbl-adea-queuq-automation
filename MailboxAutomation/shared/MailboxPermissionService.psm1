Set-StrictMode -Version Latest

function Add-MailboxFullAccess {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $exec = Resolve-MailboxExecutionContext -Identity $Data.MailboxIdentity -Config $Context.Config
    $params = @{ Identity = $Data.MailboxIdentity; User = $Data.Trustee; AccessRights = 'FullAccess'; InheritanceType = 'All' }

    switch ($exec.PermissionAuthority) {
        'OnPrem' { Add-OnPremMailboxPermissionSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode }
        'ExchangeOnline' { Add-ExoMailboxPermissionSafe -Parameters $params -Config $Context.Config -WhatIfMode:$Context.WhatIfMode }
        default { throw "Permission authority is unknown for '$($Data.MailboxIdentity)'. $($exec.Reason)" }
    }
}

function Remove-MailboxFullAccess {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $exec = Resolve-MailboxExecutionContext -Identity $Data.MailboxIdentity -Config $Context.Config
    $params = @{ Identity = $Data.MailboxIdentity; User = $Data.Trustee; AccessRights = 'FullAccess'; Confirm = $false }

    switch ($exec.PermissionAuthority) {
        'OnPrem' { Remove-OnPremMailboxPermissionSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode }
        'ExchangeOnline' { Remove-ExoMailboxPermissionSafe -Parameters $params -Config $Context.Config -WhatIfMode:$Context.WhatIfMode }
        default { throw "Permission authority is unknown for '$($Data.MailboxIdentity)'. $($exec.Reason)" }
    }
}

function Add-MailboxSendAs {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $exec = Resolve-MailboxExecutionContext -Identity $Data.MailboxIdentity -Config $Context.Config
    $params = @{ Identity = $Data.MailboxIdentity; Trustee = $Data.Trustee; AccessRights = 'SendAs'; Confirm = $false }

    switch ($exec.PermissionAuthority) {
        'OnPrem' { Add-OnPremSendAsPermissionSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode }
        'ExchangeOnline' { Add-ExoSendAsPermissionSafe -Parameters $params -Config $Context.Config -WhatIfMode:$Context.WhatIfMode }
        default { throw "Permission authority is unknown for '$($Data.MailboxIdentity)'. $($exec.Reason)" }
    }
}

function Remove-MailboxSendAs {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $exec = Resolve-MailboxExecutionContext -Identity $Data.MailboxIdentity -Config $Context.Config
    $params = @{ Identity = $Data.MailboxIdentity; Trustee = $Data.Trustee; AccessRights = 'SendAs'; Confirm = $false }

    switch ($exec.PermissionAuthority) {
        'OnPrem' { Remove-OnPremSendAsPermissionSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode }
        'ExchangeOnline' { Remove-ExoSendAsPermissionSafe -Parameters $params -Config $Context.Config -WhatIfMode:$Context.WhatIfMode }
        default { throw "Permission authority is unknown for '$($Data.MailboxIdentity)'. $($exec.Reason)" }
    }
}

Export-ModuleMember -Function @('Add-MailboxFullAccess','Remove-MailboxFullAccess','Add-MailboxSendAs','Remove-MailboxSendAs')

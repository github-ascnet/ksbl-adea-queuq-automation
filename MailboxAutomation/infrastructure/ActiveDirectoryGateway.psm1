Set-StrictMode -Version Latest

function Assert-AdModuleAvailable {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'ActiveDirectory module is not available. Install RSAT AD PowerShell components.'
    }
}

function Get-AdUserSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Identity)

    Assert-AdModuleAvailable
    Import-Module ActiveDirectory -ErrorAction Stop
    Get-ADUser -Identity $Identity -ErrorAction Stop
}

function Set-AdUserSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Set-ADUser'; Parameters = $Parameters } }
    Assert-AdModuleAvailable
    Import-Module ActiveDirectory -ErrorAction Stop
    Set-ADUser @Parameters -ErrorAction Stop
}

function New-AdUserSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'New-ADUser'; Parameters = $Parameters } }
    Assert-AdModuleAvailable
    Import-Module ActiveDirectory -ErrorAction Stop
    New-ADUser @Parameters -ErrorAction Stop
}

function Rename-AdObjectSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Rename-ADObject'; Parameters = $Parameters } }
    Assert-AdModuleAvailable
    Import-Module ActiveDirectory -ErrorAction Stop
    Rename-ADObject @Parameters -ErrorAction Stop
}

function Enable-AdAccountSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Identity, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Enable-ADAccount'; Identity = $Identity } }
    Assert-AdModuleAvailable
    Import-Module ActiveDirectory -ErrorAction Stop
    Enable-ADAccount -Identity $Identity -ErrorAction Stop
}

function Disable-AdAccountSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Identity, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Disable-ADAccount'; Identity = $Identity } }
    Assert-AdModuleAvailable
    Import-Module ActiveDirectory -ErrorAction Stop
    Disable-ADAccount -Identity $Identity -ErrorAction Stop
}

Export-ModuleMember -Function @(
    'Get-AdUserSafe',
    'Set-AdUserSafe',
    'New-AdUserSafe',
    'Rename-AdObjectSafe',
    'Enable-AdAccountSafe',
    'Disable-AdAccountSafe'
)

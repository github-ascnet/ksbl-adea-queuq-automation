Set-StrictMode -Version Latest

function Assert-AdModuleAvailable {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'ActiveDirectory module is not available. Install RSAT AD PowerShell components.'
    }
}

function Get-AdUserSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [string[]]$Properties = @()
    )

    Assert-AdModuleAvailable
    Import-Module ActiveDirectory -ErrorAction Stop

    if ($Properties -and $Properties.Count -gt 0) {
        Get-ADUser -Identity $Identity -Properties $Properties -ErrorAction Stop
    }
    else {
        Get-ADUser -Identity $Identity -ErrorAction Stop
    }
}

function Get-AdUserBySamAccountNameSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SamAccountName,
        [string[]]$Properties = @(),
        [string]$Server
    )

    Assert-AdModuleAvailable
    Import-Module ActiveDirectory -ErrorAction Stop

    $params = @{
        LDAPFilter  = "(samaccountname=$SamAccountName)"
        ErrorAction = 'Stop'
    }

    if ($Properties -and $Properties.Count -gt 0) {
        $params['Properties'] = $Properties
    }

    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $params['Server'] = $Server
    }

    Get-ADUser @params
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

function Set-AdAccountPasswordSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][securestring]$NewPassword,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Set-ADAccountPassword'; Identity = $Identity } }
    Assert-AdModuleAvailable
    Import-Module ActiveDirectory -ErrorAction Stop
    Set-ADAccountPassword -Identity $Identity -Reset -NewPassword $NewPassword -ErrorAction Stop
}

function Move-AdObjectSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Move-ADObject'; Identity = $Identity; TargetPath = $TargetPath } }
    Assert-AdModuleAvailable
    Import-Module ActiveDirectory -ErrorAction Stop
    Move-ADObject -Identity $Identity -TargetPath $TargetPath -ErrorAction Stop
}

function Set-AdGroupSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters, [bool]$WhatIfMode = $true)

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Set-ADGroup'; Parameters = $Parameters } }
    Assert-AdModuleAvailable
    Import-Module ActiveDirectory -ErrorAction Stop
    Set-ADGroup @Parameters -ErrorAction Stop
}


function Add-AdGroupMemberSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][string[]]$Members,
        [string]$Server,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Add-ADGroupMember'; Identity = $Identity; Members = $Members; Server = $Server } }
    Assert-AdModuleAvailable
    Import-Module ActiveDirectory -ErrorAction Stop
    $params = @{ Identity = $Identity; Members = $Members; ErrorAction = 'Stop' }
    if (-not [string]::IsNullOrWhiteSpace($Server)) { $params['Server'] = $Server }
    Add-ADGroupMember @params
}




function Search-AdUserByLdapFilterSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LdapFilter,
        [string[]]$Properties = @(),
        [string]$Server
    )

    Assert-AdModuleAvailable
    Import-Module ActiveDirectory -ErrorAction Stop
    $params = @{ LDAPFilter = $LdapFilter; ErrorAction = 'Stop' }
    if ($Properties -and $Properties.Count -gt 0) { $params['Properties'] = $Properties }
    if (-not [string]::IsNullOrWhiteSpace($Server)) { $params['Server'] = $Server }
    Get-ADUser @params
}

function Get-AdUsersByEmployeeIdSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$EmployeeId,
        [string[]]$Properties = @(),
        [string]$Server
    )

    Assert-AdModuleAvailable
    Import-Module ActiveDirectory -ErrorAction Stop

    $params = @{
        LDAPFilter  = "(employeeid=$EmployeeId)"
        ErrorAction = 'Stop'
    }

    if ($Properties -and $Properties.Count -gt 0) {
        $params['Properties'] = $Properties
    }

    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $params['Server'] = $Server
    }

    Get-ADUser @params
}

function Remove-AdGroupMemberSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][string[]]$Members,
        [string]$Server,
        [bool]$ConfirmRemoval = $false,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{
            Simulated = $true
            Action    = 'Remove-ADGroupMember'
            Identity  = $Identity
            Members   = $Members
            Server    = $Server
        }
    }

    Assert-AdModuleAvailable
    Import-Module ActiveDirectory -ErrorAction Stop
    $params = @{ Identity = $Identity; Members = $Members; Confirm = $ConfirmRemoval; ErrorAction = 'Stop' }
    if (-not [string]::IsNullOrWhiteSpace($Server)) { $params['Server'] = $Server }
    Remove-ADGroupMember @params
}


Export-ModuleMember -Function @(
    'Get-AdUserSafe',
    'Get-AdUserBySamAccountNameSafe',
    'Get-AdUsersByEmployeeIdSafe',
    'Search-AdUserByLdapFilterSafe',
    'Set-AdUserSafe',
    'New-AdUserSafe',
    'Rename-AdObjectSafe',
    'Enable-AdAccountSafe',
    'Disable-AdAccountSafe',
    'Set-AdAccountPasswordSafe',
    'Move-AdObjectSafe',
    'Set-AdGroupSafe',
    'Add-AdGroupMemberSafe',
    'Remove-AdGroupMemberSafe'
)

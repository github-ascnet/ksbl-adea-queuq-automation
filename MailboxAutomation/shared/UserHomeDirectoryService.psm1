Set-StrictMode -Version Latest

function Get-HomeDirectoryDataValue {
    [CmdletBinding()]
    param(
        [object]$Data,
        [string[]]$Names,
        [object]$DefaultValue = $null
    )

    foreach ($name in $Names) {
        if ($Data -and $Data.PSObject.Properties[$name]) {
            $value = $Data.$name
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                return $value
            }
        }
    }

    return $DefaultValue
}

function Get-HomeDirectoryConfigValue {
    [CmdletBinding()]
    param(
        [object]$Config,
        [string[]]$Path,
        [object]$DefaultValue = $null
    )

    $current = $Config
    foreach ($segment in $Path) {
        if ($null -eq $current) { return $DefaultValue }
        if ($current -is [hashtable]) {
            if (-not $current.ContainsKey($segment)) { return $DefaultValue }
            $current = $current[$segment]
            continue
        }
        if ($current.PSObject.Properties[$segment]) {
            $current = $current.$segment
            continue
        }
        return $DefaultValue
    }

    if ($null -eq $current) { return $DefaultValue }
    return $current
}

function New-UserHomeDirectoryResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][bool]$Success,
        [bool]$Changed = $false,
        [bool]$Simulated = $false,
        [string]$Action,
        [string]$Identity,
        [string]$HomePath,
        [string]$HomeDrive,
        [string]$Target,
        [string]$Message,
        [string]$ErrorCode,
        [object]$Output
    )

    [pscustomobject]@{
        Success   = $Success
        Changed   = $Changed
        Simulated = $Simulated
        Action    = $Action
        Identity  = $Identity
        HomePath  = $HomePath
        HomeDrive = $HomeDrive
        Target    = $Target
        Message   = $Message
        ErrorCode = $ErrorCode
        Output    = $Output
    }
}

function Resolve-HomeDirectoryIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][psobject]$Data)

    [string](Get-HomeDirectoryDataValue -Data $Data -Names @('Identity','AdObjectName','SamAccountName','TargetAdObjectName','UserPrincipalName'))
}

function Resolve-HomeDirectoryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data,
        [Parameter(Mandatory = $true)][string]$Identity
    )

    $explicit = [string](Get-HomeDirectoryDataValue -Data $Data -Names @('HomePath','HomeDirectory','TargetPath'))
    if (-not [string]::IsNullOrWhiteSpace($explicit)) { return $explicit }

    $namespaceRoot = [string](Get-HomeDirectoryConfigValue -Config $Context.Config -Path @('HomeDirectory','NamespaceRoot') -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($namespaceRoot)) {
        return (Join-Path -Path $namespaceRoot -ChildPath $Identity)
    }

    $defaultTargetRoot = [string](Get-HomeDirectoryConfigValue -Config $Context.Config -Path @('HomeDirectory','DefaultTargetRoot') -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($defaultTargetRoot)) {
        return (Join-Path -Path $defaultTargetRoot -ChildPath $Identity)
    }

    return $null
}

function Set-UserHomeDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $identity = Resolve-HomeDirectoryIdentity -Data $Data
    if ([string]::IsNullOrWhiteSpace($identity)) {
        return New-UserHomeDirectoryResult -Success $false -Changed $false -Simulated $Context.WhatIfMode -Action 'SetUserHomeDirectory' -Message 'User identity is required.' -ErrorCode 'USER_IDENTITY_MISSING'
    }

    $homePath = Resolve-HomeDirectoryPath -Context $Context -Data $Data -Identity $identity
    if ([string]::IsNullOrWhiteSpace($homePath)) {
        return New-UserHomeDirectoryResult -Success $false -Changed $false -Simulated $Context.WhatIfMode -Action 'SetUserHomeDirectory' -Identity $identity -Message 'HomePath/HomeDirectory is required or HomeDirectory.NamespaceRoot/DefaultTargetRoot must be configured.' -ErrorCode 'HOME_PATH_MISSING'
    }

    $homeDrive = [string](Get-HomeDirectoryDataValue -Data $Data -Names @('HomeDrive') -DefaultValue (Get-HomeDirectoryConfigValue -Config $Context.Config -Path @('HomeDirectory','DefaultHomeDrive') -DefaultValue 'H:'))
    $createFolder = [bool](Get-HomeDirectoryConfigValue -Config $Context.Config -Path @('HomeDirectory','CreateFolderIfMissing') -DefaultValue $true)

    $operations = @()

    try {
        if ($createFolder) {
            $operations += Ensure-FolderSafe -Path $homePath -WhatIfMode:$Context.WhatIfMode
        }

        $parameters = @{
            Identity      = $identity
            HomeDirectory = $homePath
            HomeDrive     = $homeDrive
        }
        $operations += Set-AdUserSafe -Parameters $parameters -WhatIfMode:$Context.WhatIfMode

        return New-UserHomeDirectoryResult -Success $true -Changed $true -Simulated $Context.WhatIfMode -Action 'SetUserHomeDirectory' -Identity $identity -HomePath $homePath -HomeDrive $homeDrive -Message "Home directory attributes set for '$identity'." -Output $operations
    }
    catch {
        return New-UserHomeDirectoryResult -Success $false -Changed $false -Simulated $Context.WhatIfMode -Action 'SetUserHomeDirectory' -Identity $identity -HomePath $homePath -HomeDrive $homeDrive -Message $_.Exception.Message -ErrorCode 'HOME_DIRECTORY_SET_FAILED' -Output $operations
    }
}

function Set-UserHomeDirectoryPermissions {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $identity = Resolve-HomeDirectoryIdentity -Data $Data
    if ([string]::IsNullOrWhiteSpace($identity)) {
        return New-UserHomeDirectoryResult -Success $false -Changed $false -Simulated $Context.WhatIfMode -Action 'SetUserHomeDirectoryPermissions' -Message 'User identity is required.' -ErrorCode 'USER_IDENTITY_MISSING'
    }

    $targetPath = [string](Get-HomeDirectoryDataValue -Data $Data -Names @('TargetPath','HomePath','HomeDirectory'))
    if ([string]::IsNullOrWhiteSpace($targetPath)) {
        return New-UserHomeDirectoryResult -Success $false -Changed $false -Simulated $Context.WhatIfMode -Action 'SetUserHomeDirectoryPermissions' -Identity $identity -Message 'TargetPath/HomePath/HomeDirectory is required.' -ErrorCode 'TARGET_PATH_MISSING'
    }

    $userDomain = [string](Get-HomeDirectoryDataValue -Data $Data -Names @('UserPrincipalDomain','Domain','TargetDomain') -DefaultValue (Get-HomeDirectoryConfigValue -Config $Context.Config -Path @('HomeDirectory','DefaultUserDomain') -DefaultValue $env:USERDOMAIN))

    try {
        $result = Set-LegacyHomeDirectoryAclSafe -HomeDirectoryPath $targetPath -UserPrincipalName $identity -UserPrincipalDomain $userDomain -WhatIfMode:$Context.WhatIfMode
        return New-UserHomeDirectoryResult -Success $true -Changed $true -Simulated $Context.WhatIfMode -Action 'SetUserHomeDirectoryPermissions' -Identity $identity -Target $targetPath -Message "Home directory permissions set for '$identity'." -Output $result
    }
    catch {
        return New-UserHomeDirectoryResult -Success $false -Changed $false -Simulated $Context.WhatIfMode -Action 'SetUserHomeDirectoryPermissions' -Identity $identity -Target $targetPath -Message $_.Exception.Message -ErrorCode 'HOME_DIRECTORY_ACL_FAILED'
    }
}


function Set-UserHomeDirectoryAndDfsTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    # Modernized replacement for the old Process-PersonMailboxJobs.ps1 chain:
    # Get-HomeDrive / Run-DfsUtil / Set-UserHomeDirPermissions / Update-DfsShareSettings.
    # DFS namespace handling is now delegated to DfsGateway.psm1 and uses DFSN cmdlets
    # such as Get-DfsnRoot, Get-DfsnFolderTarget, New-DfsnFolderTarget and
    # Remove-DfsnFolderTarget instead of the deprecated dfsutil.exe command line.
    $identity = Resolve-HomeDirectoryIdentity -Data $Data
    if ([string]::IsNullOrWhiteSpace($identity)) {
        return New-UserHomeDirectoryResult -Success $false -Changed $false -Simulated $Context.WhatIfMode -Action 'SetUserHomeDirectoryAndDfsTarget' -Message 'User identity is required.' -ErrorCode 'USER_IDENTITY_MISSING'
    }

    $domain = [string](Get-HomeDirectoryDataValue -Data $Data -Names @('UserPrincipalDomain','Domain','TargetDomain') -DefaultValue (Get-HomeDirectoryConfigValue -Config $Context.Config -Path @('HomeDirectory','DefaultUserDomain') -DefaultValue $env:USERDOMAIN))

    try {
        $result = Update-DfsShareSettingsSafe -SamAccountName $identity -Config $Context.Config -UserPrincipalDomain $domain -WhatIfMode:$Context.WhatIfMode
        return New-UserHomeDirectoryResult -Success ([bool]$result.Success) -Changed ([bool]$result.Changed) -Simulated $Context.WhatIfMode -Action 'SetUserHomeDirectoryAndDfsTarget' -Identity $identity -HomePath ([string]$result.DfsPath) -Target ([string]$result.DfsTarget) -Message ([string]$result.Message) -ErrorCode ([string]$result.ErrorCode) -Output $result
    }
    catch {
        return New-UserHomeDirectoryResult -Success $false -Changed $false -Simulated $Context.WhatIfMode -Action 'SetUserHomeDirectoryAndDfsTarget' -Identity $identity -Message $_.Exception.Message -ErrorCode 'USER_HOME_DFS_PROVISIONING_FAILED'
    }
}

function Update-UserLegacyDfsShareSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $identity = Resolve-HomeDirectoryIdentity -Data $Data
    if ([string]::IsNullOrWhiteSpace($identity)) {
        return New-UserHomeDirectoryResult -Success $false -Changed $false -Simulated $Context.WhatIfMode -Action 'UpdateLegacyDfsShareSettings' -Message 'User identity is required.' -ErrorCode 'USER_IDENTITY_MISSING'
    }

    $domain = [string](Get-HomeDirectoryDataValue -Data $Data -Names @('UserPrincipalDomain','Domain','TargetDomain') -DefaultValue (Get-HomeDirectoryConfigValue -Config $Context.Config -Path @('HomeDirectory','DefaultUserDomain') -DefaultValue $env:USERDOMAIN))

    try {
        $result = Update-DfsShareSettingsSafe -SamAccountName $identity -Config $Context.Config -UserPrincipalDomain $domain -WhatIfMode:$Context.WhatIfMode
        return New-UserHomeDirectoryResult -Success ([bool]$result.Success) -Changed ([bool]$result.Changed) -Simulated $Context.WhatIfMode -Action 'UpdateLegacyDfsShareSettings' -Identity $identity -Target ([string]$result.DfsTarget) -Message ([string]$result.Message) -ErrorCode ([string]$result.ErrorCode) -Output $result
    }
    catch {
        return New-UserHomeDirectoryResult -Success $false -Changed $false -Simulated $Context.WhatIfMode -Action 'UpdateLegacyDfsShareSettings' -Identity $identity -Message $_.Exception.Message -ErrorCode 'DFS_UPDATE_FAILED'
    }
}

Export-ModuleMember -Function @(
    'Set-UserHomeDirectory',
    'Set-UserHomeDirectoryPermissions',
    'Set-UserHomeDirectoryAndDfsTarget',
    'Update-UserLegacyDfsShareSettings'
)

Set-StrictMode -Version Latest

function Get-ConfigValue {
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

function Assert-DfsnModuleAvailable {
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name Get-DfsnRoot -ErrorAction SilentlyContinue)) {
        throw 'DFSN PowerShell cmdlets are not available. Install/enable the DFSN module before running DFS namespace operations.'
    }
}

function Get-DfsPathSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    [pscustomobject]@{
        Path   = $Path
        Exists = Test-Path -Path $Path
    }
}

function Get-DfsnHomeRootSafe {
    [CmdletBinding()]
    param(
        [object]$Config,
        [bool]$WhatIfMode = $true
    )

    $configuredRoot = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory', 'NamespaceRoot') -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($configuredRoot)) {
        return [pscustomobject]@{
            Simulated = $WhatIfMode
            Action    = 'Get-DfsnHomeRoot'
            Path      = $configuredRoot
            Source    = 'Config.HomeDirectory.NamespaceRoot'
            Success   = $true
        }
    }

    $rootPattern = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory', 'DfsRootNamePattern') -DefaultValue '*\HomeDrives')

    if ($WhatIfMode) {
        return [pscustomobject]@{
            Simulated = $true
            Action    = 'Get-DfsnHomeRoot'
            Path      = '\\example.test\HomeDrives'
            Source    = 'WhatIf'
            Success   = $true
        }
    }

    Assert-DfsnModuleAvailable
    $root = @(Get-DfsnRoot -ErrorAction Stop | Where-Object { $_.Path -like $rootPattern } | Select-Object -First 1)
    if (-not $root) {
        throw "No DFS namespace root matching '$rootPattern' was found."
    }

    [pscustomobject]@{
        Simulated = $false
        Action    = 'Get-DfsnHomeRoot'
        Path      = [string]$root.Path
        Source    = 'DFSN'
        Success   = $true
    }
}

function Get-DfsnFolderTargetSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Config,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return $null
    }

    Assert-DfsnModuleAvailable
    Get-DfsnFolderTarget -Path $Path -ErrorAction SilentlyContinue
}

function New-DfsnFolderTargetSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [object]$Config,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{
            Simulated  = $true
            Action     = 'New-DfsnFolderTarget'
            Path       = $Path
            TargetPath = $TargetPath
            Changed    = $true
            Success    = $true
        }
    }

    Assert-DfsnModuleAvailable
    New-DfsnFolderTarget -Path $Path -TargetPath $TargetPath -ErrorAction Stop | Out-Null

    [pscustomobject]@{
        Simulated  = $false
        Action     = 'New-DfsnFolderTarget'
        Path       = $Path
        TargetPath = $TargetPath
        Changed    = $true
        Success    = $true
    }
}

function Remove-DfsnFolderTargetSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [object]$Config,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{
            Simulated  = $true
            Action     = 'Remove-DfsnFolderTarget'
            Path       = $Path
            TargetPath = $TargetPath
            Changed    = $true
            Success    = $true
        }
    }

    Assert-DfsnModuleAvailable
    Remove-DfsnFolderTarget -Path $Path -TargetPath $TargetPath -Force -ErrorAction Stop | Out-Null

    [pscustomobject]@{
        Simulated  = $false
        Action     = 'Remove-DfsnFolderTarget'
        Path       = $Path
        TargetPath = $TargetPath
        Changed    = $true
        Success    = $true
    }
}

function Find-ExistingUserHomeDirectoryPathSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SamAccountName,
        [Parameter(Mandatory = $true)][object]$Config,
        [bool]$WhatIfMode = $true
    )

    $fileServers = @()
    $homeConfig = Get-ConfigValue -Config $Config -Path @('HomeDirectory') -DefaultValue @{}
    if ($homeConfig -is [hashtable] -and $homeConfig.ContainsKey('FileServers')) {
        $fileServers = @($homeConfig.FileServers)
    }

    if ($fileServers.Count -eq 0 -or $WhatIfMode) {
        return $null
    }

    $shareNamePattern = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory', 'ShareNamePattern') -DefaultValue 'home[_][a-z]$')
    foreach ($server in $fileServers) {
        $shares = @(Get-WmiObject -Class Win32_Share -ComputerName ([string]$server) -Filter "Name like '$shareNamePattern'" -ErrorAction Stop)
        foreach ($share in $shares) {
            $uncPath = Join-Path -Path ('\\' + [string]$server) -ChildPath ([string]$share.Name)
            if (-not (Test-Path -Path $uncPath -PathType Container)) { continue }

            $match = Get-ChildItem -Path $uncPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match [regex]::Escape($SamAccountName) } | Select-Object -First 1
            if ($match) {
                return [pscustomobject]@{
                    Simulated         = $false
                    Action            = 'Find-ExistingUserHomeDirectoryPath'
                    SamAccountName    = $SamAccountName
                    FullName          = [string]$match.FullName
                    HomeDirectoryRoot = [string]($match.FullName.Replace('\' + $SamAccountName, ''))
                    Server            = [string]$server
                    ShareName         = [string]$share.Name
                    Success           = $true
                }
            }
        }
    }

    $null
}

function Get-HomeDriveSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [bool]$WhatIfMode = $true
    )

    $homeConfig = Get-ConfigValue -Config $Config -Path @('HomeDirectory') -DefaultValue @{}
    $fileServers = @()
    if ($homeConfig -is [hashtable] -and $homeConfig.ContainsKey('FileServers')) {
        $fileServers = @($homeConfig.FileServers)
    }

    $shareNamePattern = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory', 'ShareNamePattern') -DefaultValue 'home[_][a-z]$')
    $fallbackTargetRoot = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory', 'DefaultTargetRoot') -DefaultValue '')

    if ($fileServers.Count -eq 0) {
        if (-not [string]::IsNullOrWhiteSpace($fallbackTargetRoot)) {
            return [pscustomobject]@{
                server     = $null
                path       = $fallbackTargetRoot
                unc_path   = $fallbackTargetRoot
                name       = Split-Path -Path $fallbackTargetRoot -Leaf
                free_space = $null
                dir_count  = $null
                Points     = 0
                Simulated  = $WhatIfMode
                Source     = 'Config.DefaultTargetRoot'
            }
        }

        throw 'HomeDirectory.FileServers or HomeDirectory.DefaultTargetRoot must be configured before selecting a home directory target.'
    }

    if ($WhatIfMode) {
        $server = [string]$fileServers[0]
        $share = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory', 'WhatIfShareName') -DefaultValue 'home_a')
        return [pscustomobject]@{
            server     = $server
            path       = $null
            unc_path   = "\\$server\$share"
            name       = $share
            free_space = $null
            dir_count  = $null
            Points     = 0
            Simulated  = $true
            Source     = 'WhatIf'
        }
    }

    $homeTargets = @()
    foreach ($server in $fileServers) {
        $shares = @(Get-WmiObject -Class Win32_Share -Filter "Name like '$shareNamePattern'" -ComputerName ([string]$server) -ErrorAction Stop)
        foreach ($share in $shares) {
            $diskFilter = "DeviceID='{0}'" -f $share.Path.Substring(0, 2)
            $disk = Get-WmiObject -Class 'Win32_LogicalDisk' -Filter $diskFilter -ComputerName ([string]$server) -ErrorAction Stop
            $unc = '\\{0}\{1}' -f $server, $share.Name
            $dirCount = if (Test-Path -Path $unc) { @(Get-ChildItem -Path $unc -Directory -ErrorAction SilentlyContinue).Count } else { 1 }
            $freeSpace = [double]$disk.FreeSpace
            $dirPoints = ($dirCount * 1024 * 1024 * 1024) * 10
            $homeTargets += [pscustomobject]@{
                server     = [string]$server
                path       = [string]$share.Path
                unc_path   = $unc
                name       = [string]$share.Name
                free_space = $freeSpace / 1GB
                dir_count  = $dirCount
                Points     = $freeSpace - $dirPoints
                Simulated  = $false
                Source     = 'WMI'
            }
        }
    }

    if ($homeTargets.Count -eq 0) {
        throw "No home directory target found using pattern '$shareNamePattern'."
    }

    $sort1 = @{ Expression = 'Points'; Descending = $true }
    $sort2 = @{ Expression = 'name'; Ascending = $true }
    $homeTargets | Sort-Object $sort1, $sort2 | Select-Object -First 1
}

function Set-DfsPathSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target,
        [object]$Config,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{
            Simulated  = $true
            Action     = 'Set-DfsPath'
            Provider   = 'DFSN'
            Path       = $Path
            Target     = $Target
            Changed    = $true
            Operations = @(
                [pscustomobject]@{ Action = 'New-DfsnFolderTarget'; Path = $Path; TargetPath = $Target; Simulated = $true }
            )
            Success    = $true
        }
    }

    Assert-DfsnModuleAvailable
    $operations = @()
    $existingTargets = @(Get-DfsnFolderTargetSafe -Path $Path -Config $Config -WhatIfMode:$false)

    if ($existingTargets.Count -eq 0) {
        $operations += New-DfsnFolderTargetSafe -Path $Path -TargetPath $Target -Config $Config -WhatIfMode:$false
    }
    elseif ($existingTargets | Where-Object { $_.TargetPath -eq $Target }) {
        $operations += [pscustomobject]@{
            Simulated  = $false
            Action     = 'Set-DfsPath'
            Path       = $Path
            TargetPath = $Target
            Changed    = $false
            Success    = $true
            Message    = 'DFS folder target already exists with the desired target.'
        }
    }
    else {
        foreach ($existing in $existingTargets) {
            $operations += Remove-DfsnFolderTargetSafe -Path ([string]$existing.Path) -TargetPath ([string]$existing.TargetPath) -Config $Config -WhatIfMode:$false
        }
        $operations += New-DfsnFolderTargetSafe -Path $Path -TargetPath $Target -Config $Config -WhatIfMode:$false
    }

    [pscustomobject]@{
        Simulated  = $false
        Action     = 'Set-DfsPath'
        Provider   = 'DFSN'
        Path       = $Path
        Target     = $Target
        Changed    = (@($operations | Where-Object { $_.PSObject.Properties['Changed'] -and $_.Changed }).Count -gt 0)
        Operations = $operations
        Success    = $true
    }
}

function Update-DfsShareSettingsSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SamAccountName,
        [object]$Config,
        [string]$UserPrincipalDomain,
        [bool]$WhatIfMode = $true
    )

    if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
        return [pscustomobject]@{
            Success   = $false
            Changed   = $false
            Simulated = $WhatIfMode
            Action    = 'Update-DfsShareSettings'
            Message   = 'SamAccountName is required.'
            ErrorCode = 'SAMACCOUNTNAME_MISSING'
        }
    }

    if ([string]::IsNullOrWhiteSpace($UserPrincipalDomain)) {
        $UserPrincipalDomain = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory', 'DefaultUserDomain') -DefaultValue $env:USERDOMAIN)
    }

    $applicationDirectoryShare = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory', 'ApplicationDirectoryShare') -DefaultValue '')
    $desktopDirectoryShare = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory', 'DesktopDirectoryShare') -DefaultValue '')
    $deletedMarker = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory', 'DeletedHomeDirectoryMarker') -DefaultValue '.delete_manually_user_left_company')

    $operations = @()

    try {
        $dfsRoot = Get-DfsnHomeRootSafe -Config $Config -WhatIfMode:$WhatIfMode
        $existingHome = Find-ExistingUserHomeDirectoryPathSafe -SamAccountName $SamAccountName -Config $Config -WhatIfMode:$WhatIfMode
        $homeDirectoryRoot = $null
        $physicalHomePath = $null
        $homeDrive = $null

        if ($existingHome) {
            $physicalHomePath = [string]$existingHome.FullName
            if ($physicalHomePath.Contains($deletedMarker)) {
                $restoredPath = $physicalHomePath.Replace($deletedMarker, '')
                $newName = Split-Path -Path $restoredPath -Leaf
                $operations += Rename-FolderSafe -Path $physicalHomePath -NewName $newName -WhatIfMode:$WhatIfMode
                $physicalHomePath = $restoredPath
            }
            $homeDirectoryRoot = $physicalHomePath.Replace('\' + $SamAccountName, '')
            $homeDrive = [pscustomobject]@{
                unc_path  = $homeDirectoryRoot
                Source    = 'ExistingHomeDirectory'
                Simulated = $WhatIfMode
            }
        }
        else {
            $homeDrive = Get-HomeDriveSafe -Config $Config -WhatIfMode:$WhatIfMode
            $homeDirectoryRoot = [string]$homeDrive.unc_path
            $physicalHomePath = Join-Path -Path $homeDirectoryRoot -ChildPath $SamAccountName
        }

        $operations += Ensure-FolderSafe -Path $physicalHomePath -WhatIfMode:$WhatIfMode
        $operations += Set-LegacyHomeDirectoryAclSafe -HomeDirectoryPath $physicalHomePath -UserPrincipalName $SamAccountName -UserPrincipalDomain $UserPrincipalDomain -WhatIfMode:$WhatIfMode

        $dfsPath = Join-Path -Path ([string]$dfsRoot.Path) -ChildPath $SamAccountName
        $operations += Set-DfsPathSafe -Path $dfsPath -Target $physicalHomePath -Config $Config -WhatIfMode:$WhatIfMode

        if (-not [string]::IsNullOrWhiteSpace($applicationDirectoryShare)) {
            $operations += Set-LegacyApplicationDirectoryAclSafe -ApplicationDirectoryPath $applicationDirectoryShare -UserPrincipalName $SamAccountName -UserPrincipalDomain $UserPrincipalDomain -WhatIfMode:$WhatIfMode
        }

        if (-not [string]::IsNullOrWhiteSpace($desktopDirectoryShare)) {
            $operations += Set-LegacyApplicationDirectoryAclSafe -ApplicationDirectoryPath $desktopDirectoryShare -UserPrincipalName $SamAccountName -UserPrincipalDomain $UserPrincipalDomain -WhatIfMode:$WhatIfMode
        }

        [pscustomobject]@{
            Success        = $true
            Changed        = $true
            Simulated      = $WhatIfMode
            Action         = 'Update-DfsShareSettings'
            Provider       = 'DFSN'
            SamAccountName = $SamAccountName
            DfsRoot        = [string]$dfsRoot.Path
            DfsPath        = $dfsPath
            DfsTarget      = $physicalHomePath
            HomeDrive      = $homeDrive
            ExistingHome   = $existingHome
            Operations     = $operations
            Message        = "DFSN home directory target and permissions updated for '$SamAccountName'."
            ErrorCode      = $null
        }
    }
    catch {
        [pscustomobject]@{
            Success        = $false
            Changed        = $false
            Simulated      = $WhatIfMode
            Action         = 'Update-DfsShareSettings'
            Provider       = 'DFSN'
            SamAccountName = $SamAccountName
            Message        = $_.Exception.Message
            ErrorCode      = 'DFSN_UPDATE_FAILED'
            Operations     = $operations
        }
    }
}

Export-ModuleMember -Function @(
    'Get-DfsPathSafe',
    'Get-DfsnHomeRootSafe',
    'Get-DfsnFolderTargetSafe',
    'New-DfsnFolderTargetSafe',
    'Remove-DfsnFolderTargetSafe',
    'Find-ExistingUserHomeDirectoryPathSafe',
    'Get-HomeDriveSafe',
    'Set-DfsPathSafe',
    'Update-DfsShareSettingsSafe'
)

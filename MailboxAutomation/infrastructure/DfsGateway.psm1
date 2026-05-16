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

function Get-DfsPathSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    [pscustomobject]@{
        Path   = $Path
        Exists = Test-Path -Path $Path
    }
}

function Invoke-DfsUtilSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Arguments,
        [object]$Config,
        [bool]$WhatIfMode = $true
    )

    $dfsUtilPath = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory','DfsUtilPath') -DefaultValue 'd:\iam\dfsutil.exe')

    if ($WhatIfMode) {
        return [pscustomobject]@{
            Simulated = $true
            Action    = 'dfsutil'
            FileName  = $dfsUtilPath
            Arguments = $Arguments
            ExitCode  = 0
            Success   = $true
        }
    }

    if (-not (Test-Path -Path $dfsUtilPath -PathType Leaf)) {
        throw "DFSUtil executable not found: $dfsUtilPath"
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.FileName = $dfsUtilPath
    $process.StartInfo.Arguments = $Arguments
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.UseShellExecute = $false
    [void]$process.Start()
    [void]$process.WaitForExit()

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $exitCode = $process.ExitCode
    $process.Dispose()

    if ($exitCode -ne 0) {
        throw "DFSUtil failed with exit code $exitCode. StdOut: $stdout StdErr: $stderr"
    }

    [pscustomobject]@{
        Simulated = $false
        Action    = 'dfsutil'
        FileName  = $dfsUtilPath
        Arguments = $Arguments
        ExitCode  = $exitCode
        StdOut    = $stdout
        StdErr    = $stderr
        Success   = $true
    }
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

    $shareNamePattern = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory','ShareNamePattern') -DefaultValue 'home_[a-z]')
    $fallbackTargetRoot = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory','DefaultTargetRoot') -DefaultValue '')

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

        throw 'HomeDirectory.FileServers or HomeDirectory.DefaultTargetRoot must be configured before selecting a home drive.'
    }

    if ($WhatIfMode) {
        $server = [string]$fileServers[0]
        $share = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory','WhatIfShareName') -DefaultValue 'home_a')
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
        $wmiParams = @{
            Class        = 'Win32_Share'
            Filter       = "Name like '$shareNamePattern'"
            ComputerName = [string]$server
        }

        $shares = @(Get-WmiObject @wmiParams -ErrorAction Stop)
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
        throw "No home drive target found using pattern '$shareNamePattern'."
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

    $arguments = 'link add "{0}" "{1}"' -f $Path, $Target
    $dfsResult = Invoke-DfsUtilSafe -Arguments $arguments -Config $Config -WhatIfMode:$WhatIfMode

    [pscustomobject]@{
        Simulated = $WhatIfMode
        Action    = 'Set-DfsPath'
        Path      = $Path
        Target    = $Target
        DfsUtil   = $dfsResult
        Success   = $true
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
        $UserPrincipalDomain = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory','DefaultUserDomain') -DefaultValue $env:USERDOMAIN)
    }

    $namespaceRoot = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory','NamespaceRoot') -DefaultValue '')
    $applicationDirectoryShare = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory','ApplicationDirectoryShare') -DefaultValue '')
    $desktopDirectoryShare = [string](Get-ConfigValue -Config $Config -Path @('HomeDirectory','DesktopDirectoryShare') -DefaultValue '')

    $operations = @()

    try {
        $homeDrive = Get-HomeDriveSafe -Config $Config -WhatIfMode:$WhatIfMode
        $dfsTarget = Join-Path -Path ([string]$homeDrive.unc_path) -ChildPath $SamAccountName

        $operations += Set-LegacyHomeDirectoryAclSafe -HomeDirectoryPath $dfsTarget -UserPrincipalName $SamAccountName -UserPrincipalDomain $UserPrincipalDomain -WhatIfMode:$WhatIfMode

        if (-not [string]::IsNullOrWhiteSpace($namespaceRoot)) {
            $dfsPath = Join-Path -Path $namespaceRoot -ChildPath $SamAccountName
            $operations += Set-DfsPathSafe -Path $dfsPath -Target $dfsTarget -Config $Config -WhatIfMode:$WhatIfMode
        }
        else {
            $operations += [pscustomobject]@{
                Simulated = $WhatIfMode
                Action    = 'Set-DfsPath'
                Skipped   = $true
                Reason    = 'HomeDirectory.NamespaceRoot is not configured.'
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($applicationDirectoryShare)) {
            $operations += Set-LegacyApplicationDirectoryAclSafe -ApplicationDirectoryPath $applicationDirectoryShare -UserPrincipalName $SamAccountName -UserPrincipalDomain $UserPrincipalDomain -WhatIfMode:$WhatIfMode
        }

        if (-not [string]::IsNullOrWhiteSpace($desktopDirectoryShare)) {
            $operations += Set-LegacyApplicationDirectoryAclSafe -ApplicationDirectoryPath $desktopDirectoryShare -UserPrincipalName $SamAccountName -UserPrincipalDomain $UserPrincipalDomain -WhatIfMode:$WhatIfMode
        }

        [pscustomobject]@{
            Success      = $true
            Changed      = $true
            Simulated    = $WhatIfMode
            Action       = 'Update-DfsShareSettings'
            SamAccountName = $SamAccountName
            HomeDrive    = $homeDrive
            DfsTarget    = $dfsTarget
            Operations   = $operations
            Message      = "DFS home/application/desktop settings updated for '$SamAccountName'."
            ErrorCode    = $null
        }
    }
    catch {
        [pscustomobject]@{
            Success      = $false
            Changed      = $false
            Simulated    = $WhatIfMode
            Action       = 'Update-DfsShareSettings'
            SamAccountName = $SamAccountName
            Message      = $_.Exception.Message
            ErrorCode    = 'DFS_UPDATE_FAILED'
            Operations   = $operations
        }
    }
}

Export-ModuleMember -Function @(
    'Get-DfsPathSafe',
    'Invoke-DfsUtilSafe',
    'Get-HomeDriveSafe',
    'Set-DfsPathSafe',
    'Update-DfsShareSettingsSafe'
)

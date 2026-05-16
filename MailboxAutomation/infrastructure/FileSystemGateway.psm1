Set-StrictMode -Version Latest

function Test-FolderExistsSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    [pscustomobject]@{
        Path   = $Path
        Exists = (Test-Path -Path $Path -PathType Container)
    }
}

function Ensure-Folder {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }

    $Path
}

function Ensure-FolderSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{
            Simulated = $true
            Action    = 'Ensure-Folder'
            Path      = $Path
            Changed   = -not (Test-Path -Path $Path -PathType Container -ErrorAction SilentlyContinue)
        }
    }

    if (-not (Test-Path -Path $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
        return [pscustomobject]@{ Simulated = $false; Action = 'Ensure-Folder'; Path = $Path; Changed = $true }
    }

    [pscustomobject]@{ Simulated = $false; Action = 'Ensure-Folder'; Path = $Path; Changed = $false }
}

function Ensure-LegacyHomeDirectorySubfoldersSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectoryPath,
        [bool]$WhatIfMode = $true
    )

    $folders = @(
        $HomeDirectoryPath,
        (Join-Path -Path $HomeDirectoryPath -ChildPath 'SYSTEM_FOLDER'),
        (Join-Path -Path $HomeDirectoryPath -ChildPath 'SYSTEM_FOLDER\Vorlagen'),
        (Join-Path -Path $HomeDirectoryPath -ChildPath 'SYSTEM_FOLDER\Outlook'),
        (Join-Path -Path $HomeDirectoryPath -ChildPath 'SYSTEM_FOLDER\Signatures'),
        (Join-Path -Path $HomeDirectoryPath -ChildPath 'SYSTEM_FOLDER\Favoriten')
    )

    $results = @()
    foreach ($folder in $folders) {
        $results += Ensure-FolderSafe -Path $folder -WhatIfMode:$WhatIfMode
    }

    [pscustomobject]@{
        Simulated = $WhatIfMode
        Action    = 'Ensure-LegacyHomeDirectorySubfolders'
        Path      = $HomeDirectoryPath
        Folders   = $results
    }
}

function Set-FolderAclSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$User,
        [string]$AccessRight = 'Modify',
        [string]$Inheritance = 'ContainerInherit,ObjectInherit',
        [string]$Propagation = 'None',
        [bool]$ProtectAcl = $true,
        [bool]$KeepAdministratorsOnly = $false,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{
            Simulated              = $true
            Action                 = 'Set-FolderAcl'
            Path                   = $Path
            User                   = $User
            AccessRight            = $AccessRight
            Inheritance            = $Inheritance
            Propagation            = $Propagation
            ProtectAcl             = $ProtectAcl
            KeepAdministratorsOnly = $KeepAdministratorsOnly
        }
    }

    if (-not (Test-Path -Path $Path -PathType Container)) {
        throw "Folder '$Path' does not exist."
    }

    $acl = Get-Acl -Path $Path -ErrorAction Stop

    if ($KeepAdministratorsOnly) {
        foreach ($access in @($acl.Access)) {
            if ([string]$access.IdentityReference.Value -ne 'BUILTIN\Administrators') {
                [void]$acl.RemoveAccessRule($access)
            }
        }
    }
    else {
        foreach ($access in @($acl.Access)) {
            if ([string]$access.IdentityReference.Value -eq $User) {
                [void]$acl.RemoveAccessRule($access)
            }
        }
    }

    if ($ProtectAcl) {
        $acl.SetAccessRuleProtection($true, $false)
    }

    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        'BUILTIN\Administrators',
        'FullControl',
        [System.Security.AccessControl.InheritanceFlags]$Inheritance,
        [System.Security.AccessControl.PropagationFlags]$Propagation,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    [void]$acl.AddAccessRule($adminRule)

    $userRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $User,
        $AccessRight,
        [System.Security.AccessControl.InheritanceFlags]$Inheritance,
        [System.Security.AccessControl.PropagationFlags]$Propagation,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    [void]$acl.AddAccessRule($userRule)

    Set-Acl -Path $Path -AclObject $acl -ErrorAction Stop

    [pscustomobject]@{
        Simulated   = $false
        Action      = 'Set-FolderAcl'
        Path        = $Path
        User        = $User
        AccessRight = $AccessRight
        Changed     = $true
    }
}

function Set-LegacyHomeDirectoryAclSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$HomeDirectoryPath,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [Parameter(Mandatory = $true)][string]$UserPrincipalDomain,
        [bool]$WhatIfMode = $true
    )

    $user = "$UserPrincipalDomain\$UserPrincipalName"
    $folders = Ensure-LegacyHomeDirectorySubfoldersSafe -HomeDirectoryPath $HomeDirectoryPath -WhatIfMode:$WhatIfMode
    $acl = Set-FolderAclSafe -Path $HomeDirectoryPath -User $user -AccessRight 'Modify' -Inheritance 'ContainerInherit,ObjectInherit' -Propagation 'None' -ProtectAcl:$true -KeepAdministratorsOnly:$false -WhatIfMode:$WhatIfMode

    [pscustomobject]@{
        Simulated = $WhatIfMode
        Action    = 'Set-LegacyHomeDirectoryAcl'
        Path      = $HomeDirectoryPath
        User      = $user
        Folders   = $folders
        Acl       = $acl
    }
}

function Set-LegacyApplicationDirectoryAclSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ApplicationDirectoryPath,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [Parameter(Mandatory = $true)][string]$UserPrincipalDomain,
        [bool]$WhatIfMode = $true
    )

    $targetPath = Join-Path -Path $ApplicationDirectoryPath -ChildPath $UserPrincipalName
    Ensure-FolderSafe -Path $targetPath -WhatIfMode:$WhatIfMode | Out-Null
    $user = "$UserPrincipalDomain\$UserPrincipalName"
    $acl = Set-FolderAclSafe -Path $targetPath -User $user -AccessRight 'Modify' -Inheritance 'ContainerInherit,ObjectInherit' -Propagation 'None' -ProtectAcl:$true -KeepAdministratorsOnly:$true -WhatIfMode:$WhatIfMode

    [pscustomobject]@{
        Simulated = $WhatIfMode
        Action    = 'Set-LegacyApplicationDirectoryAcl'
        Path      = $targetPath
        User      = $user
        Acl       = $acl
    }
}

function Move-FileSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{ Simulated = $true; Source = $Source; Destination = $Destination }
    }

    Move-Item -Path $Source -Destination $Destination -Force -ErrorAction Stop
}

function Copy-FileSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{ Simulated = $true; Source = $Source; Destination = $Destination }
    }

    Copy-Item -Path $Source -Destination $Destination -Force -ErrorAction Stop
}

Export-ModuleMember -Function @(
    'Ensure-Folder',
    'Ensure-FolderSafe',
    'Test-FolderExistsSafe',
    'Ensure-LegacyHomeDirectorySubfoldersSafe',
    'Set-FolderAclSafe',
    'Set-LegacyHomeDirectoryAclSafe',
    'Set-LegacyApplicationDirectoryAclSafe',
    'Move-FileSafe',
    'Copy-FileSafe'
)

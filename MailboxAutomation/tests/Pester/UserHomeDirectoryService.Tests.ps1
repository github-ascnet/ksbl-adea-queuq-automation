$root = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

Import-Module -Name (Join-Path $root 'infrastructure\FileSystemGateway.psm1') -Force
Import-Module -Name (Join-Path $root 'infrastructure\DfsGateway.psm1') -Force
Import-Module -Name (Join-Path $root 'infrastructure\ActiveDirectoryGateway.psm1') -Force
Import-Module -Name (Join-Path $root 'shared\UserHomeDirectoryService.psm1') -Force
Import-Module -Name (Join-Path $root 'shared\PersonMailboxService.psm1') -Force

function New-HomeDirectoryTestContext {
    [CmdletBinding()]
    param([bool]$WhatIfMode = $true)

    [pscustomobject]@{
        WhatIfMode = $WhatIfMode
        Logger     = $null
        Config     = @{
            HomeDirectory = @{
                DefaultHomeDrive         = 'H:'
                CreateFolderIfMissing   = $true
                SetPermissions           = $true
                NamespaceRoot            = '\\example.test\HomeDrives'
                DefaultTargetRoot        = '\\fileserver\home_a'
                FileServers              = @()
                WhatIfShareName          = 'home_a'
                DefaultUserDomain        = 'EXAMPLE'
                ApplicationDirectoryShare = '\\fileserver\Appdata$'
                DesktopDirectoryShare     = '\\fileserver\Desktop$'
                DfsUtilPath              = 'd:\iam\dfsutil.exe'
            }
        }
        Services   = [pscustomobject]@{}
    }
}

Describe 'UserHomeDirectoryService legacy migration' {
    It 'Set-UserHomeDirectory returns HOME_PATH_MISSING when no path and no configured default exists' {
        $context = [pscustomobject]@{
            WhatIfMode = $true
            Config = @{ HomeDirectory = @{ DefaultHomeDrive = 'H:' } }
            Logger = $null
        }
        $result = Set-UserHomeDirectory -Context $context -Data ([pscustomobject]@{ Identity = 'ex01234' })
        $result.Success | Should -BeFalse
        $result.ErrorCode | Should -Be 'HOME_PATH_MISSING'
    }

    It 'Set-UserHomeDirectory returns USER_IDENTITY_MISSING when identity is missing' {
        $context = New-HomeDirectoryTestContext
        $result = Set-UserHomeDirectory -Context $context -Data ([pscustomobject]@{ HomePath = '\\example.test\HomeDrives\ex01234' })
        $result.Success | Should -BeFalse
        $result.ErrorCode | Should -Be 'USER_IDENTITY_MISSING'
    }

    It 'Set-UserHomeDirectory simulates folder creation and AD homeDirectory/homeDrive update' {
        $context = New-HomeDirectoryTestContext
        $result = Set-UserHomeDirectory -Context $context -Data ([pscustomobject]@{ Identity = 'ex01234' })
        $result.Success | Should -BeTrue
        $result.Simulated | Should -BeTrue
        $result.HomePath | Should -Be '\\example.test\HomeDrives\ex01234'
        $result.HomeDrive | Should -Be 'H:'
        @($result.Output).Count | Should -BeGreaterThan 0
    }

    It 'Set-UserHomeDirectoryPermissions validates target path' {
        $context = New-HomeDirectoryTestContext
        $result = Set-UserHomeDirectoryPermissions -Context $context -Data ([pscustomobject]@{ Identity = 'ex01234' })
        $result.Success | Should -BeFalse
        $result.ErrorCode | Should -Be 'TARGET_PATH_MISSING'
    }

    It 'Set-UserHomeDirectoryPermissions simulates legacy home ACL logic' {
        $context = New-HomeDirectoryTestContext
        $result = Set-UserHomeDirectoryPermissions -Context $context -Data ([pscustomobject]@{ Identity = 'ex01234'; TargetPath = '\\fileserver\home_a\ex01234' })
        $result.Success | Should -BeTrue
        $result.Simulated | Should -BeTrue
        $result.Output.Action | Should -Be 'Set-LegacyHomeDirectoryAcl'
    }

    It 'Update-UserLegacyDfsShareSettings simulates Get-HomeDrive, home ACL, dfsutil and application/desktop permissions' {
        $context = New-HomeDirectoryTestContext
        $result = Update-UserLegacyDfsShareSettings -Context $context -Data ([pscustomobject]@{ Identity = 'ex01234'; UserPrincipalDomain = 'EXAMPLE' })
        $result.Success | Should -BeTrue
        $result.Simulated | Should -BeTrue
        $result.Output.Action | Should -Be 'Update-DfsShareSettings'
        @($result.Output.Operations).Count | Should -BeGreaterThan 2
        @($result.Output.Operations | Where-Object { $_.Action -eq 'Set-DfsPath' }).Count | Should -Be 1
        @($result.Output.Operations | Where-Object { $_.Action -eq 'Set-LegacyApplicationDirectoryAcl' }).Count | Should -Be 2
    }

    It 'Get-HomeDriveSafe returns configured fallback target when no WMI servers are configured' {
        $context = New-HomeDirectoryTestContext
        $result = Get-HomeDriveSafe -Config $context.Config -WhatIfMode:$true
        $result.unc_path | Should -Be '\\fileserver\home_a'
        $result.Source | Should -Be 'Config.DefaultTargetRoot'
    }
}

Describe 'PersonMailbox finalization DFS migration' {
    It 'Complete-NonStandardPersonMailboxProvisioning advertises legacy DFS finalization in WhatIf output' {
        $context = New-HomeDirectoryTestContext
        $context | Add-Member -NotePropertyName Services -NotePropertyValue ([pscustomobject]@{
            UserHomeDirectory = [pscustomobject]@{
                UpdateDfsShares = { param($Context, $Data) Update-UserLegacyDfsShareSettings -Context $Context -Data $Data }
            }
        }) -Force

        $row = [pscustomobject]@{
            ActionType              = 'CreateNonStdPersonMailbox'
            TargetAdObjectName       = 'ex01234'
            TargetDomain             = 'EXAMPLE'
            TargetUserDomainOU       = 'OU=External,DC=example,DC=test'
            TargetUserAdDisplayname  = 'Muster Max'
            TargetUserAdGivenname    = 'Max'
            TargetUserAdSurname      = 'Muster'
            TargetUserAdEmployeeType = 'P'
            TargetLocation           = 'LI'
            MailboxEnable            = 'true'
            CurrentUserName          = 'Requester'
            CurrentUserDomainName    = 'EXAMPLE'
            CurrentUserEMailAddress  = 'requester@example.test'
        }

        $result = Complete-NonStandardPersonMailboxProvisioning -Context $context -Data $row
        $result.Success | Should -BeTrue
        $result.Simulated | Should -BeTrue
        @($result.Output | Where-Object { $_.Action -eq 'Update-DfsShareSettings' }).Count | Should -Be 1
    }
}

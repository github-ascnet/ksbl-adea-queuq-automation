Set-StrictMode -Version Latest

$root = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

Import-Module -Name (Join-Path $root 'core\JobResult.psm1')                                   -Force
Import-Module -Name (Join-Path $root 'core\Logging.psm1')                                     -Force
Import-Module -Name (Join-Path $root 'core\Validation.psm1')                                  -Force
Import-Module -Name (Join-Path $root 'infrastructure\ActiveDirectoryGateway.psm1')            -Force
Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnPremGateway.psm1')             -Force
Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnlineGateway.psm1')             -Force
Import-Module -Name (Join-Path $root 'infrastructure\HybridMailboxResolver.psm1')             -Force
Import-Module -Name (Join-Path $root 'shared\UserProvisioningService.psm1')                   -Force
Import-Module -Name (Join-Path $root 'usecases\GenericUser\RenameUserAccount.psm1')           -Force
Import-Module -Name (Join-Path $root 'usecases\GenericUser\ChangeAccountSurname.psm1')        -Force
Import-Module -Name (Join-Path $root 'usecases\GenericUser\AddEmailNickname.psm1')            -Force

# ---------------------------------------------------------------------------
# Shared test infrastructure
# ---------------------------------------------------------------------------

BeforeAll {
    function New-TestLogger {
        [pscustomobject]@{
            RunId           = 'test-hybrid-gu'
            LogFile         = (Join-Path $TestDrive 'hybrid-gu.log')
            ConsoleEnabled  = $false
            FileEnabled     = $false
            EventLogEnabled = $false
            EventLogName    = 'Application'
            EventSource     = 'AdeaJobEngine.Tests'
            VerboseLogging  = $false
        }
    }

    function New-TestConfig {
        param([bool]$ExoEnabled = $false)
        @{
            ExchangeOnline = @{
                Enabled        = $ExoEnabled
                AppId          = 'test-app-id'
                CertThumbprint = 'test-thumbprint'
                Organization   = 'test.onmicrosoft.com'
                TenantDomain   = 'test.onmicrosoft.com'
            }
        }
    }

    function New-TestContext {
        param(
            [bool]$ExoEnabled  = $false,
            [bool]$WhatIfMode  = $false,
            [scriptblock]$RenameUser       = $null,
            [scriptblock]$SetSurname       = $null,
            [scriptblock]$AddEmailNickname = $null
        )
        $rename = if ($RenameUser)       { $RenameUser }       else { { param($C, $D) [pscustomobject]@{ Success = $true; RequiresRetry = $false } } }
        $surname = if ($SetSurname)      { $SetSurname }       else { { param($C, $D) [pscustomobject]@{ Success = $true; RequiresRetry = $false } } }
        $nick    = if ($AddEmailNickname){ $AddEmailNickname }  else { { param($C, $D) [pscustomobject]@{ Success = $true; RequiresRetry = $false; Changed = $true } } }
        [pscustomobject]@{
            Config     = (New-TestConfig -ExoEnabled $ExoEnabled)
            Logger     = (New-TestLogger)
            WhatIfMode = $WhatIfMode
            Payload    = @()
            Services   = [pscustomobject]@{
                UserProvisioning = [pscustomobject]@{
                    RenameUser       = $rename
                    SetSurname       = $surname
                    AddEmailNickname = $nick
                }
            }
        }
    }

    function New-RenameRow {
        param(
            [string]$AdObjectName          = 'gn-rename',
            [string]$TargetAdObjectName    = 'gn-renamed',
            [string]$NewUserId             = 'gn-renamed',
            [string]$GivenName             = 'New',
            [string]$SurName               = 'Name',
            [string]$NewPrimaryEMailAddress = 'new@example.com'
        )
        [pscustomobject]@{
            ActionType              = 'RenameUserAccount'
            AdObjectName            = $AdObjectName
            TargetAdObjectName      = $TargetAdObjectName
            NewUserId               = $NewUserId
            GivenName               = $GivenName
            SurName                 = $SurName
            NewPrimaryEMailAddress  = $NewPrimaryEMailAddress
            CurrentUserName         = 'Tester'
            CurrentUserDomainName   = 'DOMAIN'
            CurrentUserEMailAddress = 'tester@example.org'
        }
    }

    function New-SurnameRow {
        param(
            [string]$AdObjectName          = 'gn-surname',
            [string]$GivenName             = 'Given',
            [string]$SurName               = 'Updated',
            [string]$NewPrimaryEMailAddress = 'updated@example.com'
        )
        [pscustomobject]@{
            ActionType              = 'ChangeAccountSurname'
            AdObjectName            = $AdObjectName
            GivenName               = $GivenName
            SurName                 = $SurName
            NewPrimaryEMailAddress  = $NewPrimaryEMailAddress
            CurrentUserName         = 'Tester'
            CurrentUserDomainName   = 'DOMAIN'
            CurrentUserEMailAddress = 'tester@example.org'
        }
    }

    function New-NicknameRow {
        param(
            [string]$AdObjectName          = 'gn-nick',
            [string]$NewPrimaryEMailAddress = 'new-primary@example.com'
        )
        [pscustomobject]@{
            ActionType              = 'AddEmailNickname'
            AdObjectName            = $AdObjectName
            NewPrimaryEMailAddress  = $NewPrimaryEMailAddress
            CurrentUserName         = 'Tester'
            CurrentUserDomainName   = 'DOMAIN'
            CurrentUserEMailAddress = 'tester@example.org'
        }
    }

    function New-MockAdUser {
        param([string]$Sam = 'gn-test')
        [pscustomobject]@{
            SamAccountName    = $Sam
            DistinguishedName = "CN=$Sam,OU=GenericUsers,DC=example,DC=com"
            DisplayName       = 'Old Display'
            GivenName         = 'Old'
            Surname           = 'Display'
            mail              = 'old@example.com'
        }
    }

    function New-MockMailbox {
        param([string]$Alias = 'gn-test', [string]$PrimarySmtp = 'old@example.com')
        [pscustomobject]@{
            Alias              = $Alias
            PrimarySmtpAddress = $PrimarySmtp
        }
    }

    # Preset resolver snapshots for UserProvisioningService mock tests
    $script:ExecUserMailbox = [pscustomobject]@{
        Identity = 'gn-test'; ExistsOnPrem = $true; ExistsInExchangeOnline = $false
        RecipientTypeDetails = 'UserMailbox'; IdentityAuthority = 'OnPremAD'
        AttributeAuthority = 'OnPremAD'; RecipientAuthority = 'OnPremExchange'
        MailboxAuthority = 'OnPremExchange'; ManagementAuthority = 'OnPremExchange'
        PermissionAuthority = 'OnPremExchange'; IsSynchronized = $false; IsCloudOnly = $false
        IsMigrationTransient = $false; RecommendedAction = 'Execute'; RetryAfterMinutes = 15
        Reason = 'On-prem UserMailbox found.'
    }

    $script:ExecRemoteUser = [pscustomobject]@{
        Identity = 'gn-test'; ExistsOnPrem = $true; ExistsInExchangeOnline = $false
        RecipientTypeDetails = 'RemoteUserMailbox'; IdentityAuthority = 'OnPremAD'
        AttributeAuthority = 'OnPremAD'; RecipientAuthority = 'OnPremExchange'
        MailboxAuthority = 'ExchangeOnline'; ManagementAuthority = 'ExchangeOnline'
        PermissionAuthority = 'ExchangeOnline'; IsSynchronized = $true; IsCloudOnly = $false
        IsMigrationTransient = $false; RecommendedAction = 'Execute'; RetryAfterMinutes = 15
        Reason = 'RemoteUserMailbox found. Synchronized attributes can be managed via On-Prem Exchange.'
    }

    $script:ExecCloudOnly = [pscustomobject]@{
        Identity = 'gn-test'; ExistsOnPrem = $false; ExistsInExchangeOnline = $true
        RecipientTypeDetails = 'UserMailbox'; IdentityAuthority = 'ExchangeOnline'
        AttributeAuthority = 'ExchangeOnline'; RecipientAuthority = 'ExchangeOnline'
        MailboxAuthority = 'ExchangeOnline'; ManagementAuthority = 'ExchangeOnline'
        PermissionAuthority = 'ExchangeOnline'; IsSynchronized = $false; IsCloudOnly = $true
        IsMigrationTransient = $false; RecommendedAction = 'Execute'; RetryAfterMinutes = 15
        Reason = 'EXO-only mailbox found.'
    }

    $script:ExecNotFound = [pscustomobject]@{
        Identity = 'gn-test'; ExistsOnPrem = $false; ExistsInExchangeOnline = $false
        RecipientTypeDetails = $null; IdentityAuthority = 'Unknown'
        AttributeAuthority = 'ExchangeOnline'; RecipientAuthority = 'Unknown'
        MailboxAuthority = 'Unknown'; ManagementAuthority = 'Unknown'
        PermissionAuthority = 'Unknown'; IsSynchronized = $false; IsCloudOnly = $false
        IsMigrationTransient = $false; RecommendedAction = 'Fail'; RetryAfterMinutes = 15
        Reason = "Identity 'gn-test' not found on-prem or in Exchange Online."
    }

    $script:ExecExoDisabled = [pscustomobject]@{
        Identity = 'gn-test'; ExistsOnPrem = $true; ExistsInExchangeOnline = $false
        RecipientTypeDetails = 'RemoteSharedMailbox'; IdentityAuthority = 'OnPremAD'
        AttributeAuthority = 'OnPremAD'; RecipientAuthority = 'OnPremExchange'
        MailboxAuthority = 'OnPremExchange'; ManagementAuthority = 'ExchangeOnline'
        PermissionAuthority = 'ExchangeOnline'; IsSynchronized = $true; IsCloudOnly = $false
        IsMigrationTransient = $false; RecommendedAction = 'Fail'; RetryAfterMinutes = 15
        Reason = 'RemoteSharedMailbox found but EXO is disabled.'
    }

    $script:ExecMigrationRetry = [pscustomobject]@{
        Identity = 'gn-test'; ExistsOnPrem = $true; ExistsInExchangeOnline = $false
        RecipientTypeDetails = 'RemoteSharedMailbox'; IdentityAuthority = 'OnPremAD'
        AttributeAuthority = 'OnPremAD'; RecipientAuthority = 'OnPremExchange'
        MailboxAuthority = 'OnPremExchange'; ManagementAuthority = 'ExchangeOnline'
        PermissionAuthority = 'ExchangeOnline'; IsSynchronized = $true; IsCloudOnly = $false
        IsMigrationTransient = $true; RecommendedAction = 'Retry'; RetryAfterMinutes = 15
        Reason = 'Mailbox in transient migration state. Retry after 15 minutes.'
    }
}

# ===========================================================================
# 1. HybridMailboxResolver â€” GenericUser recipient types
# ===========================================================================

Describe 'HybridMailboxResolver.Resolve-MailboxExecutionContext â€” GenericUser types' {

    Context 'On-Prem UserMailbox' {
        It 'returns OnPremExchange RecipientAuthority and Execute action' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'UserMailbox' }
            }
            $config = @{ ExchangeOnline = @{ Enabled = $false } }
            $result = Resolve-MailboxExecutionContext -Identity 'gn-user' -Config $config
            $result.RecipientAuthority  | Should -Be 'OnPremExchange'
            $result.PermissionAuthority | Should -Be 'OnPremExchange'
            $result.RecommendedAction   | Should -Be 'Execute'
            $result.IsSynchronized      | Should -Be $false
            $result.IsCloudOnly         | Should -Be $false
            $result.ExistsOnPrem        | Should -Be $true
        }

        It 'returns IdentityAuthority OnPremAD for on-prem object' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'UserMailbox' }
            }
            $config = @{ ExchangeOnline = @{ Enabled = $false } }
            $result = Resolve-MailboxExecutionContext -Identity 'gn-user' -Config $config
            $result.IdentityAuthority | Should -Be 'OnPremAD'
        }
    }

    Context 'On-Prem RemoteUserMailbox' {
        It 'returns OnPremExchange RecipientAuthority with Execute and IsSynchronized=true' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'RemoteUserMailbox' }
            }
            $config = @{ ExchangeOnline = @{ Enabled = $false } }
            $result = Resolve-MailboxExecutionContext -Identity 'gn-remote' -Config $config
            $result.RecipientAuthority  | Should -Be 'OnPremExchange'
            $result.PermissionAuthority | Should -Be 'ExchangeOnline'
            $result.RecommendedAction   | Should -Be 'Execute'
            $result.IsSynchronized      | Should -Be $true
            $result.IsCloudOnly         | Should -Be $false
        }

        It 'does not trigger EXO lookup for RemoteUserMailbox even when EXO is enabled' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'RemoteUserMailbox' }
            }
            Mock -ModuleName 'HybridMailboxResolver' Get-ExoRecipientSafe { throw 'EXO should not be called for RemoteUserMailbox' }
            $config = @{ ExchangeOnline = @{ Enabled = $true; AppId = 'x'; CertThumbprint = 'x'; Organization = 'x'; TenantDomain = 'x' } }
            # Should NOT throw â€” EXO lookup should be skipped for RemoteUserMailbox
            { Resolve-MailboxExecutionContext -Identity 'gn-remote' -Config $config } | Should -Not -Throw
        }

        It 'returns Execute regardless of EXO visibility (synchronized attributes go On-Prem)' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'RemoteUserMailbox' }
            }
            $config = @{ ExchangeOnline = @{ Enabled = $true; AppId = 'x'; CertThumbprint = 'x'; Organization = 'x'; TenantDomain = 'x' } }
            $result = Resolve-MailboxExecutionContext -Identity 'gn-remote' -Config $config
            $result.RecommendedAction | Should -Be 'Execute'
        }
    }

    Context 'EXO-only object (no on-prem proxy)' {
        It 'returns ExchangeOnline RecipientAuthority and IsCloudOnly=true' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe { $null }
            Mock -ModuleName 'HybridMailboxResolver' Get-ExoRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'UserMailbox' }
            }
            $config = @{ ExchangeOnline = @{ Enabled = $true; AppId = 'x'; CertThumbprint = 'x'; Organization = 'x'; TenantDomain = 'x' } }
            $result = Resolve-MailboxExecutionContext -Identity 'cloud-user' -Config $config
            $result.RecipientAuthority  | Should -Be 'ExchangeOnline'
            $result.PermissionAuthority | Should -Be 'ExchangeOnline'
            $result.IsCloudOnly         | Should -Be $true
            $result.IsSynchronized      | Should -Be $false
            $result.IdentityAuthority   | Should -Be 'ExchangeOnline'
        }
    }

    Context 'Recipient not found anywhere' {
        It 'returns Unknown authority with Fail and IdentityAuthority Unknown' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe { $null }
            Mock -ModuleName 'HybridMailboxResolver' Get-ExoRecipientSafe    { $null }
            $config = @{ ExchangeOnline = @{ Enabled = $true; AppId = 'x'; CertThumbprint = 'x'; Organization = 'x'; TenantDomain = 'x' } }
            $result = Resolve-MailboxExecutionContext -Identity 'missing' -Config $config
            $result.RecipientAuthority  | Should -Be 'Unknown'
            $result.PermissionAuthority | Should -Be 'Unknown'
            $result.RecommendedAction   | Should -Be 'Fail'
            $result.IdentityAuthority   | Should -Be 'Unknown'
            $result.IsCloudOnly         | Should -Be $false
        }
    }
}

# ===========================================================================
# 2. UserProvisioningService.Rename-GenericUser â€” hybrid routing
# ===========================================================================

Describe 'UserProvisioningService.Rename-GenericUser â€” hybrid routing' {

    Context 'WhatIf mode' {
        It 'returns a simulated result without calling any gateway' {
            $ctx = [pscustomobject]@{
                Config     = (New-TestConfig -ExoEnabled $false)
                Logger     = New-TestLogger
                WhatIfMode = $true
            }
            $row = New-RenameRow
            $result = Rename-GenericUser -Context $ctx -Data $row
            $result.Success   | Should -Be $true
            $result.Simulated | Should -Be $true
            $result.Changed   | Should -Be $true
        }
    }

    Context 'On-Prem UserMailbox routing' {
        BeforeEach {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecUserMailbox }
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe  { New-MockAdUser -Sam 'gn-rename' }
            Mock -ModuleName 'UserProvisioningService' Rename-AdObjectSafe         {}
            Mock -ModuleName 'UserProvisioningService' Set-AdUserSafe              {}
            Mock -ModuleName 'UserProvisioningService' Set-OnPremMailboxSafe       {}
            Mock -ModuleName 'UserProvisioningService' Set-OnPremRemoteMailboxSafe {}
        }

        It 'calls Set-OnPremMailboxSafe (not Set-OnPremRemoteMailboxSafe) for UserMailbox' {
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            Rename-GenericUser -Context $ctx -Data (New-RenameRow) | Out-Null
            Should -Invoke 'Set-OnPremMailboxSafe'       -ModuleName 'UserProvisioningService' -Times 1
            Should -Invoke 'Set-OnPremRemoteMailboxSafe' -ModuleName 'UserProvisioningService' -Times 0
        }

        It 'returns Success=true, Changed=true' {
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            $result = Rename-GenericUser -Context $ctx -Data (New-RenameRow)
            $result.Success | Should -Be $true
            $result.Changed | Should -Be $true
        }
    }

    Context 'RemoteUserMailbox routing' {
        BeforeEach {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecRemoteUser }
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe  { New-MockAdUser -Sam 'gn-rename' }
            Mock -ModuleName 'UserProvisioningService' Rename-AdObjectSafe         {}
            Mock -ModuleName 'UserProvisioningService' Set-AdUserSafe              {}
            Mock -ModuleName 'UserProvisioningService' Set-OnPremMailboxSafe       {}
            Mock -ModuleName 'UserProvisioningService' Set-OnPremRemoteMailboxSafe {}
        }


        It 'calls Set-OnPremRemoteMailboxSafe (not Set-OnPremMailboxSafe) for RemoteUserMailbox' {
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            Rename-GenericUser -Context $ctx -Data (New-RenameRow) | Out-Null
            Should -Invoke 'Set-OnPremRemoteMailboxSafe' -ModuleName 'UserProvisioningService' -Times 1
            Should -Invoke 'Set-OnPremMailboxSafe'       -ModuleName 'UserProvisioningService' -Times 0
        }
    }

    Context 'Cloud-only recipient' {
        It 'returns CLOUD_ONLY_NOT_SUPPORTED' {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecCloudOnly }
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            $result = Rename-GenericUser -Context $ctx -Data (New-RenameRow)
            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'CLOUD_ONLY_NOT_SUPPORTED'
        }
    }

    Context 'Recipient not found' {
        It 'returns RECIPIENT_NOT_FOUND when resolver returns Unknown/Fail' {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecNotFound }
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            $result = Rename-GenericUser -Context $ctx -Data (New-RenameRow)
            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'RECIPIENT_NOT_FOUND'
        }
    }

    Context 'AD user not found' {
        It 'returns AD_OBJECT_NOT_FOUND when AD user does not exist' {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecUserMailbox }
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe  { $null }
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            $result = Rename-GenericUser -Context $ctx -Data (New-RenameRow)
            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'AD_OBJECT_NOT_FOUND'
        }
    }
}

# ===========================================================================
# 3. UserProvisioningService.Set-GenericUserSurname â€” hybrid routing
# ===========================================================================

Describe 'UserProvisioningService.Set-GenericUserSurname â€” hybrid routing' {

    Context 'WhatIf mode' {
        It 'returns a simulated result without calling any gateway' {
            $ctx = [pscustomobject]@{
                Config     = (New-TestConfig -ExoEnabled $false)
                Logger     = New-TestLogger
                WhatIfMode = $true
            }
            $result = Set-GenericUserSurname -Context $ctx -Data (New-SurnameRow)
            $result.Success   | Should -Be $true
            $result.Simulated | Should -Be $true
        }
    }

    Context 'On-Prem UserMailbox routing' {
        BeforeEach {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecUserMailbox }
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe  { New-MockAdUser -Sam 'gn-surname' }
            Mock -ModuleName 'UserProvisioningService' Get-ObjectPropertyValue        { 'gn-surname' }
            Mock -ModuleName 'UserProvisioningService' Set-AdUserSafe              {}
            Mock -ModuleName 'UserProvisioningService' Set-OnPremMailboxSafe       {}
            Mock -ModuleName 'UserProvisioningService' Set-OnPremRemoteMailboxSafe {}
        }

        It 'calls Set-OnPremMailboxSafe for UserMailbox' {
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            Set-GenericUserSurname -Context $ctx -Data (New-SurnameRow) | Out-Null
            Should -Invoke 'Set-OnPremMailboxSafe'       -ModuleName 'UserProvisioningService' -Times 1
            Should -Invoke 'Set-OnPremRemoteMailboxSafe' -ModuleName 'UserProvisioningService' -Times 0
        }
    }

    Context 'RemoteUserMailbox routing' {
        BeforeEach {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecRemoteUser }
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe  { New-MockAdUser -Sam 'gn-surname' }
            Mock -ModuleName 'UserProvisioningService' Get-ObjectPropertyValue        { 'gn-surname' }
            Mock -ModuleName 'UserProvisioningService' Set-AdUserSafe              {}
            Mock -ModuleName 'UserProvisioningService' Set-OnPremMailboxSafe       {}
            Mock -ModuleName 'UserProvisioningService' Set-OnPremRemoteMailboxSafe {}
        }

        It 'calls Set-OnPremRemoteMailboxSafe for RemoteUserMailbox' {
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            Set-GenericUserSurname -Context $ctx -Data (New-SurnameRow) | Out-Null
            Should -Invoke 'Set-OnPremRemoteMailboxSafe' -ModuleName 'UserProvisioningService' -Times 1
            Should -Invoke 'Set-OnPremMailboxSafe'       -ModuleName 'UserProvisioningService' -Times 0
        }
    }

    Context 'Cloud-only recipient' {
        It 'returns CLOUD_ONLY_NOT_SUPPORTED' {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecCloudOnly }
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            $result = Set-GenericUserSurname -Context $ctx -Data (New-SurnameRow)
            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'CLOUD_ONLY_NOT_SUPPORTED'
        }
    }

    Context 'Recipient not found' {
        It 'returns RECIPIENT_NOT_FOUND' {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecNotFound }
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            $result = Set-GenericUserSurname -Context $ctx -Data (New-SurnameRow)
            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'RECIPIENT_NOT_FOUND'
        }
    }
}

# ===========================================================================
# 4. UserProvisioningService.Add-GenericUserEmailNickname â€” hybrid routing
# ===========================================================================

Describe 'UserProvisioningService.Add-GenericUserEmailNickname â€” hybrid routing' {

    Context 'WhatIf mode' {
        It 'returns a simulated result without calling the resolver or any gateway' {
            $ctx = [pscustomobject]@{
                Config     = (New-TestConfig -ExoEnabled $false)
                Logger     = New-TestLogger
                WhatIfMode = $true
            }
            $result = Add-GenericUserEmailNickname -Context $ctx -Data (New-NicknameRow)
            $result.Success   | Should -Be $true
            $result.Simulated | Should -Be $true
            $result.Action    | Should -Be 'Set-Mailbox'
        }
    }

    Context 'On-Prem UserMailbox routing' {
        BeforeEach {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecUserMailbox }
            Mock -ModuleName 'UserProvisioningService' Get-OnPremMailboxSafe       { New-MockMailbox -PrimarySmtp 'old@example.com' }
            Mock -ModuleName 'UserProvisioningService' Get-OnPremRemoteMailboxSafe {}
            Mock -ModuleName 'UserProvisioningService' Set-OnPremMailboxSafe       {}
            Mock -ModuleName 'UserProvisioningService' Set-OnPremRemoteMailboxSafe {}
        }

        It 'uses Get-OnPremMailboxSafe and Set-OnPremMailboxSafe for UserMailbox' {
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            $result = Add-GenericUserEmailNickname -Context $ctx -Data (New-NicknameRow)
            $result.Success | Should -Be $true
            $result.Changed | Should -Be $true
            Should -Invoke 'Get-OnPremMailboxSafe'          -ModuleName 'UserProvisioningService' -Times 1
            Should -Invoke 'Set-OnPremMailboxSafe'          -ModuleName 'UserProvisioningService' -Times 1
            Should -Invoke 'Get-OnPremRemoteMailboxSafe'    -ModuleName 'UserProvisioningService' -Times 0
            Should -Invoke 'Set-OnPremRemoteMailboxSafe'    -ModuleName 'UserProvisioningService' -Times 0
        }
    }

    Context 'RemoteUserMailbox routing' {
        BeforeEach {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecRemoteUser }
            Mock -ModuleName 'UserProvisioningService' Get-OnPremMailboxSafe       {}
            Mock -ModuleName 'UserProvisioningService' Get-OnPremRemoteMailboxSafe { New-MockMailbox -PrimarySmtp 'old@example.com' }
            Mock -ModuleName 'UserProvisioningService' Set-OnPremMailboxSafe       {}
            Mock -ModuleName 'UserProvisioningService' Set-OnPremRemoteMailboxSafe {}
        }

        It 'uses Get-OnPremRemoteMailboxSafe and Set-OnPremRemoteMailboxSafe for RemoteUserMailbox' {
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            $result = Add-GenericUserEmailNickname -Context $ctx -Data (New-NicknameRow)
            $result.Success | Should -Be $true
            $result.Changed | Should -Be $true
            Should -Invoke 'Get-OnPremRemoteMailboxSafe'    -ModuleName 'UserProvisioningService' -Times 1
            Should -Invoke 'Set-OnPremRemoteMailboxSafe'    -ModuleName 'UserProvisioningService' -Times 1
            Should -Invoke 'Get-OnPremMailboxSafe'          -ModuleName 'UserProvisioningService' -Times 0
            Should -Invoke 'Set-OnPremMailboxSafe'          -ModuleName 'UserProvisioningService' -Times 0
        }
    }

    Context 'No-change: address already equals current primary' {
        It 'returns Success=true and Changed=false without calling Set-*' {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecUserMailbox }
            # Current primary is the SAME as the requested new primary
            Mock -ModuleName 'UserProvisioningService' Get-OnPremMailboxSafe       { New-MockMailbox -PrimarySmtp 'new-primary@example.com' }
            Mock -ModuleName 'UserProvisioningService' Set-OnPremMailboxSafe       {}
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            $result = Add-GenericUserEmailNickname -Context $ctx -Data (New-NicknameRow -NewPrimaryEMailAddress 'new-primary@example.com')
            $result.Success | Should -Be $true
            $result.Changed | Should -Be $false
            Should -Invoke 'Set-OnPremMailboxSafe' -ModuleName 'UserProvisioningService' -Times 0
        }
    }

    Context 'Cloud-only recipient' {
        It 'returns CLOUD_ONLY_NOT_SUPPORTED' {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecCloudOnly }
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            $result = Add-GenericUserEmailNickname -Context $ctx -Data (New-NicknameRow)
            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'CLOUD_ONLY_NOT_SUPPORTED'
        }
    }

    Context 'EXO required but disabled (RemoteSharedMailbox with EXO off)' {
        It 'returns EXO_REQUIRED_BUT_DISABLED' {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecExoDisabled }
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            $result = Add-GenericUserEmailNickname -Context $ctx -Data (New-NicknameRow)
            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'EXO_REQUIRED_BUT_DISABLED'
        }
    }

    Context 'Transient migration state (Retry)' {
        It 'returns RequiresRetry=true and MAILBOX_MIGRATION_TRANSIENT error code' {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecMigrationRetry }
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            $result = Add-GenericUserEmailNickname -Context $ctx -Data (New-NicknameRow)
            $result.Success       | Should -Be $false
            $result.RequiresRetry | Should -Be $true
            $result.ErrorCode     | Should -Be 'MAILBOX_MIGRATION_TRANSIENT'
        }
    }

    Context 'Recipient not found' {
        It 'returns RECIPIENT_NOT_FOUND when resolver returns Unknown/Fail' {
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecNotFound }
            $ctx = [pscustomobject]@{ Config = (New-TestConfig); Logger = New-TestLogger; WhatIfMode = $false }
            $result = Add-GenericUserEmailNickname -Context $ctx -Data (New-NicknameRow)
            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'RECIPIENT_NOT_FOUND'
        }
    }
}

# ===========================================================================
# 5. Handler: Invoke-RenameUserAccount â€” RequiresRetry propagation
# ===========================================================================

Describe 'Invoke-RenameUserAccount handler â€” RequiresRetry propagation' {

    Context 'Service returns RequiresRetry=true' {
        It 'returns a Retry job result' {
            $svc = { param($Ctx, $Data) [pscustomobject]@{ Success = $false; RequiresRetry = $true; RetryAfterMinutes = 15; Message = 'Transient state.' } }
            $ctx = New-TestContext -RenameUser $svc
            $ctx.Payload = @(New-RenameRow)
            $result = Invoke-RenameUserAccount -Context $ctx
            $result.Status | Should -Be 'Retry'
        }
    }

    Context 'Service returns Success=true' {
        It 'returns a Succeeded job result' {
            $svc = { param($Ctx, $Data) [pscustomobject]@{ Success = $true; RequiresRetry = $false; Changed = $true; Message = 'Done.' } }
            $ctx = New-TestContext -RenameUser $svc
            $ctx.Payload = @(New-RenameRow)
            $result = Invoke-RenameUserAccount -Context $ctx
            $result.Status | Should -Be 'Succeeded'
        }
    }

    Context 'Service returns Success=false' {
        It 'returns a Failed job result with PARTIAL_FAILURE' {
            $svc = { param($Ctx, $Data) [pscustomobject]@{ Success = $false; RequiresRetry = $false; ErrorCode = 'AD_OBJECT_NOT_FOUND'; Message = 'Not found.' } }
            $ctx = New-TestContext -RenameUser $svc
            $ctx.Payload = @(New-RenameRow)
            $result = Invoke-RenameUserAccount -Context $ctx
            $result.Status    | Should -Be 'Failed'
            $result.ErrorCode | Should -Be 'PARTIAL_FAILURE'
        }
    }

    Context 'Validation failure (missing required field)' {
        It 'returns a USECASE_ERROR job result when required CSV fields are missing' {
            $ctx = New-TestContext
            $ctx.Payload = @([pscustomobject]@{ ActionType = 'RenameUserAccount' }) # missing fields
            $result = Invoke-RenameUserAccount -Context $ctx
            $result.Status    | Should -Be 'Failed'
            $result.ErrorCode | Should -Be 'USECASE_ERROR'
        }
    }
}

# ===========================================================================
# 6. Handler: Invoke-ChangeAccountSurname â€” RequiresRetry propagation
# ===========================================================================

Describe 'Invoke-ChangeAccountSurname handler â€” RequiresRetry propagation' {

    Context 'Service returns RequiresRetry=true' {
        It 'returns a Retry job result' {
            $svc = { param($Ctx, $Data) [pscustomobject]@{ Success = $false; RequiresRetry = $true; RetryAfterMinutes = 15; Message = 'Transient state.' } }
            $ctx = New-TestContext -SetSurname $svc
            $ctx.Payload = @(New-SurnameRow)
            $result = Invoke-ChangeAccountSurname -Context $ctx
            $result.Status | Should -Be 'Retry'
        }
    }

    Context 'Service returns Success=true' {
        It 'returns a Succeeded job result' {
            $svc = { param($Ctx, $Data) [pscustomobject]@{ Success = $true; RequiresRetry = $false; Changed = $true; Message = 'Done.' } }
            $ctx = New-TestContext -SetSurname $svc
            $ctx.Payload = @(New-SurnameRow)
            $result = Invoke-ChangeAccountSurname -Context $ctx
            $result.Status | Should -Be 'Succeeded'
        }
    }
}

# ===========================================================================
# 7. Handler: Invoke-AddEmailNickname â€” RequiresRetry propagation
# ===========================================================================

Describe 'Invoke-AddEmailNickname handler â€” RequiresRetry propagation' {

    Context 'Service returns RequiresRetry=true' {
        It 'returns a Retry job result' {
            $svc = { param($Ctx, $Data) [pscustomobject]@{ Success = $false; RequiresRetry = $true; RetryAfterMinutes = 15; Message = 'Transient state.' } }
            $ctx = New-TestContext -AddEmailNickname $svc
            $ctx.Payload = @(New-NicknameRow)
            $result = Invoke-AddEmailNickname -Context $ctx
            $result.Status | Should -Be 'Retry'
        }
    }

    Context 'Service returns Success=true, Changed=true' {
        It 'returns a Succeeded job result' {
            $svc = { param($Ctx, $Data) [pscustomobject]@{ Success = $true; RequiresRetry = $false; Changed = $true; Message = 'Done.' } }
            $ctx = New-TestContext -AddEmailNickname $svc
            $ctx.Payload = @(New-NicknameRow)
            $result = Invoke-AddEmailNickname -Context $ctx
            $result.Status | Should -Be 'Succeeded'
        }
    }

    Context 'Service returns Success=true, Changed=false (no-change)' {
        It 'returns a Succeeded job result even when nothing changed' {
            $svc = { param($Ctx, $Data) [pscustomobject]@{ Success = $true; RequiresRetry = $false; Changed = $false; Message = 'Already set.' } }
            $ctx = New-TestContext -AddEmailNickname $svc
            $ctx.Payload = @(New-NicknameRow)
            $result = Invoke-AddEmailNickname -Context $ctx
            $result.Status | Should -Be 'Succeeded'
        }
    }

    Context 'Service returns Success=false' {
        It 'returns a Failed job result with ADD_EMAIL_NICKNAME_FAILED' {
            $svc = { param($Ctx, $Data) [pscustomobject]@{ Success = $false; RequiresRetry = $false; ErrorCode = 'RECIPIENT_NOT_FOUND'; Message = 'Not found.' } }
            $ctx = New-TestContext -AddEmailNickname $svc
            $ctx.Payload = @(New-NicknameRow)
            $result = Invoke-AddEmailNickname -Context $ctx
            $result.Status    | Should -Be 'Failed'
            $result.ErrorCode | Should -Be 'ADD_EMAIL_NICKNAME_FAILED'
        }
    }
}

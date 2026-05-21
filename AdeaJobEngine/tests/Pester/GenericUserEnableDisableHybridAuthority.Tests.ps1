$root = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

Import-Module -Name (Join-Path $root 'core\JobResult.psm1')        -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'core\Validation.psm1')       -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'core\Logging.psm1')          -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'infrastructure\ActiveDirectoryGateway.psm1')   -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnPremGateway.psm1')    -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnlineGateway.psm1')    -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'infrastructure\DfsGateway.psm1')               -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'infrastructure\HybridMailboxResolver.psm1')    -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'shared\MailboxFeatureService.psm1')            -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'shared\UserProvisioningService.psm1')          -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'usecases\GenericUser\EnableGenericUser.psm1')  -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'usecases\GenericUser\DisableGenericUser.psm1') -Force -DisableNameChecking

BeforeAll {
    function New-TestLogger {
        [pscustomobject]@{
            RunId           = 'test'
            LogFile         = (Join-Path $TestDrive 'test.log')
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
                Enabled              = $ExoEnabled
                TenantDomain         = 'contoso.onmicrosoft.com'
                Organization         = 'contoso.onmicrosoft.com'
                AppId                = '00000000-0000-0000-0000-000000000000'
                CertificateThumbprint = '0000000000000000000000000000000000000000'
            }
        }
    }

    function New-TestContext {
        param(
            [object[]]$Payload = @(),
            [hashtable]$Services = $null,
            [bool]$WhatIfMode = $false,
            [bool]$ExoEnabled = $false
        )
        if (-not $Services) {
            $Services = @{
                UserProvisioning = [pscustomobject]@{
                    EnableUser  = { param($Ctx, $D) Enable-GenericUser  -Context $Ctx -Data $D }
                    DisableUser = { param($Ctx, $D) Disable-GenericUser -Context $Ctx -Data $D }
                }
            }
        }
        [pscustomobject]@{
            Payload    = $Payload
            Logger     = New-TestLogger
            WhatIfMode = $WhatIfMode
            Config     = New-TestConfig -ExoEnabled $ExoEnabled
            Services   = [pscustomobject]$Services
        }
    }

    function New-EnableRow {
        param([string]$AdObjectName = 'gn-enable')
        [pscustomobject]@{
            ActionType              = 'EnableNonStdPersonMailbox'
            AdObjectName            = $AdObjectName
            CurrentUserName         = 'Requester'
            CurrentUserDomainName   = 'DOMAIN'
            CurrentUserEMailAddress = 'requester@example.org'
        }
    }

    function New-DisableRow {
        param([string]$AdObjectName = 'gn-disable')
        [pscustomobject]@{
            ActionType              = 'DisableNonStdPersonMailbox'
            AdObjectName            = $AdObjectName
            CurrentUserName         = 'Requester'
            CurrentUserDomainName   = 'DOMAIN'
            CurrentUserEMailAddress = 'requester@example.org'
        }
    }

    function New-MockAdUser {
        param(
            [string]$Sam = 'gn-enable',
            [string]$Mail = 'gn-enable@example.org',
            [string]$MailNickname = 'gn-enable',
            [string]$HomeMdb = '',
            [bool]$Enabled = $false,
            [string]$Dn = 'CN=gn-enable,OU=Users,DC=example,DC=com'
        )
        [pscustomobject]@{
            SamAccountName        = $Sam
            mail                  = $Mail
            mailNickname          = $MailNickname
            homeMdb               = $HomeMdb
            extensionAttribute11  = ''
            Enabled               = $Enabled
            DistinguishedName     = $Dn
        }
    }

    # Preset resolver snapshots (used in MockWith scriptblocks via $script: scope)

    # UserMailbox — on-prem mailbox; all operations stay on-prem
    $script:ExecUserMailbox = [pscustomobject]@{
        Identity               = 'gn-enable@example.org'
        ExistsOnPrem           = $true
        ExistsInExchangeOnline = $false
        RecipientTypeDetails   = 'UserMailbox'
        IdentityAuthority      = 'OnPremAD'
        AttributeAuthority     = 'OnPremAD'
        RecipientAuthority     = 'OnPremExchange'
        MailboxAuthority       = 'OnPremExchange'
        FeatureAuthority       = 'OnPremExchange'
        PermissionAuthority    = 'OnPremExchange'
        ManagementAuthority    = 'OnPremExchange'
        IsSynchronized         = $false
        IsCloudOnly            = $false
        IsMigrationTransient   = $false
        RecommendedAction      = 'Execute'
        RetryAfterMinutes      = 15
        Reason                 = 'UserMailbox found on-prem.'
    }

    # RemoteUserMailbox — on-prem proxy, mailbox in EXO; synchronized features via Set-RemoteMailbox
    $script:ExecRemoteUser = [pscustomobject]@{
        Identity               = 'gn-enable@example.org'
        ExistsOnPrem           = $true
        ExistsInExchangeOnline = $false
        RecipientTypeDetails   = 'RemoteUserMailbox'
        IdentityAuthority      = 'OnPremAD'
        AttributeAuthority     = 'OnPremAD'
        RecipientAuthority     = 'OnPremExchange'
        MailboxAuthority       = 'OnPremExchange'
        FeatureAuthority       = 'OnPremExchange'
        PermissionAuthority    = 'ExchangeOnline'
        ManagementAuthority    = 'ExchangeOnline'
        IsSynchronized         = $true
        IsCloudOnly            = $false
        IsMigrationTransient   = $false
        RecommendedAction      = 'Execute'
        RetryAfterMinutes      = 15
        Reason                 = 'RemoteUserMailbox found on-prem. Synchronized attributes managed via On-Prem Exchange.'
    }

    # EXO-only — no on-prem proxy; not supported for GenericUser Enable/Disable
    $script:ExecCloudOnly = [pscustomobject]@{
        Identity               = 'gn-enable@example.org'
        ExistsOnPrem           = $false
        ExistsInExchangeOnline = $true
        RecipientTypeDetails   = 'UserMailbox'
        IdentityAuthority      = 'ExchangeOnline'
        AttributeAuthority     = 'ExchangeOnline'
        RecipientAuthority     = 'ExchangeOnline'
        MailboxAuthority       = 'ExchangeOnline'
        FeatureAuthority       = 'ExchangeOnline'
        PermissionAuthority    = 'ExchangeOnline'
        ManagementAuthority    = 'ExchangeOnline'
        IsSynchronized         = $false
        IsCloudOnly            = $true
        IsMigrationTransient   = $false
        RecommendedAction      = 'Execute'
        RetryAfterMinutes      = 15
        Reason                 = 'EXO-only mailbox found.'
    }

    # Retry — migration transient state (RemoteSharedMailbox, EXO not yet visible)
    $script:ExecRetry = [pscustomobject]@{
        Identity               = 'gn-enable@example.org'
        ExistsOnPrem           = $true
        ExistsInExchangeOnline = $false
        RecipientTypeDetails   = 'RemoteSharedMailbox'
        IdentityAuthority      = 'OnPremAD'
        AttributeAuthority     = 'OnPremAD'
        RecipientAuthority     = 'OnPremExchange'
        MailboxAuthority       = 'OnPremExchange'
        FeatureAuthority       = 'OnPremExchange'
        PermissionAuthority    = 'ExchangeOnline'
        ManagementAuthority    = 'ExchangeOnline'
        IsSynchronized         = $true
        IsCloudOnly            = $false
        IsMigrationTransient   = $true
        RecommendedAction      = 'Retry'
        RetryAfterMinutes      = 15
        Reason                 = 'RemoteSharedMailbox found on-prem but EXO mailbox not yet visible. Transient migration sync state.'
    }

    # EXO disabled — RemoteSharedMailbox with EXO configuration disabled
    $script:ExecExoDisabled = [pscustomobject]@{
        Identity               = 'gn-enable@example.org'
        ExistsOnPrem           = $true
        ExistsInExchangeOnline = $false
        RecipientTypeDetails   = 'RemoteSharedMailbox'
        IdentityAuthority      = 'OnPremAD'
        AttributeAuthority     = 'OnPremAD'
        RecipientAuthority     = 'OnPremExchange'
        MailboxAuthority       = 'OnPremExchange'
        FeatureAuthority       = 'ExchangeOnline'
        PermissionAuthority    = 'ExchangeOnline'
        ManagementAuthority    = 'ExchangeOnline'
        IsSynchronized         = $true
        IsCloudOnly            = $false
        IsMigrationTransient   = $false
        RecommendedAction      = 'Fail'
        RetryAfterMinutes      = 15
        Reason                 = 'RemoteSharedMailbox found but Exchange Online is disabled.'
    }
}

# ---------------------------------------------------------------------------
# 1. HybridMailboxResolver — FeatureAuthority for GenericUser recipient types
# ---------------------------------------------------------------------------
Describe 'HybridMailboxResolver.Resolve-MailboxExecutionContext — FeatureAuthority for GenericUser types' {

    Context 'UserMailbox (on-prem)' {
        It 'returns FeatureAuthority=OnPremExchange for UserMailbox' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'UserMailbox' }
            }
            $result = Resolve-MailboxExecutionContext -Identity 'user@example.org' -Config @{}
            $result.FeatureAuthority | Should -Be 'OnPremExchange'
        }

        It 'returns RecommendedAction=Execute and IsSynchronized=false for UserMailbox' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'UserMailbox' }
            }
            $result = Resolve-MailboxExecutionContext -Identity 'user@example.org' -Config @{}
            $result.RecommendedAction | Should -Be 'Execute'
            $result.IsSynchronized   | Should -Be $false
            $result.IsCloudOnly      | Should -Be $false
        }
    }

    Context 'RemoteUserMailbox (on-prem proxy, mailbox in EXO)' {
        It 'returns FeatureAuthority=OnPremExchange for RemoteUserMailbox' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'RemoteUserMailbox' }
            }
            $result = Resolve-MailboxExecutionContext -Identity 'remote@example.org' -Config @{}
            $result.FeatureAuthority | Should -Be 'OnPremExchange'
        }

        It 'returns IsSynchronized=true, PermissionAuthority=ExchangeOnline, RecommendedAction=Execute for RemoteUserMailbox' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'RemoteUserMailbox' }
            }
            $result = Resolve-MailboxExecutionContext -Identity 'remote@example.org' -Config @{}
            $result.IsSynchronized      | Should -Be $true
            $result.PermissionAuthority | Should -Be 'ExchangeOnline'
            $result.RecommendedAction   | Should -Be 'Execute'
        }

        It 'does NOT trigger EXO lookup for RemoteUserMailbox (EXO enabled but no EXO call expected)' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'RemoteUserMailbox' }
            }
            Mock -ModuleName 'HybridMailboxResolver' Get-ExoRecipientSafe {}
            $cfg = @{ ExchangeOnline = @{ Enabled = $true } }
            $result = Resolve-MailboxExecutionContext -Identity 'remote@example.org' -Config $cfg
            Should -Invoke 'Get-ExoRecipientSafe' -ModuleName 'HybridMailboxResolver' -Times 0
            $result.FeatureAuthority | Should -Be 'OnPremExchange'
        }
    }

    Context 'EXO-only object (no on-prem proxy)' {
        It 'returns FeatureAuthority=ExchangeOnline and IsCloudOnly=true for EXO-only object' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe { $null }
            Mock -ModuleName 'HybridMailboxResolver' Get-ExoRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'UserMailbox' }
            }
            $cfg = @{ ExchangeOnline = @{ Enabled = $true } }
            $result = Resolve-MailboxExecutionContext -Identity 'exo@example.org' -Config $cfg
            $result.FeatureAuthority | Should -Be 'ExchangeOnline'
            $result.IsCloudOnly      | Should -Be $true
            $result.IdentityAuthority| Should -Be 'ExchangeOnline'
        }
    }

    Context 'Object not found anywhere' {
        It 'returns FeatureAuthority=Unknown and RecommendedAction=Fail when not found' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe { $null }
            Mock -ModuleName 'HybridMailboxResolver' Get-ExoRecipientSafe { $null }
            $cfg = @{ ExchangeOnline = @{ Enabled = $true } }
            $result = Resolve-MailboxExecutionContext -Identity 'nobody@example.org' -Config $cfg
            $result.FeatureAuthority  | Should -Be 'Unknown'
            $result.RecommendedAction | Should -Be 'Fail'
            $result.IdentityAuthority | Should -Be 'Unknown'
        }
    }
}

# ---------------------------------------------------------------------------
# 2. MailboxFeatureService — Set-MailboxVisibility hybrid routing
# ---------------------------------------------------------------------------
Describe 'MailboxFeatureService.Set-MailboxVisibility — hybrid routing' {

    Context 'UserMailbox (no Resolution)' {
        It 'calls Set-OnPremMailboxSafe when no Resolution provided' {
            Mock -ModuleName 'MailboxFeatureService' Set-OnPremMailboxSafe       {}
            Mock -ModuleName 'MailboxFeatureService' Set-OnPremRemoteMailboxSafe {}

            Set-MailboxVisibility -MailboxName 'gn-test' -Visibility 'Hide' -WhatIfMode $false

            Should -Invoke 'Set-OnPremMailboxSafe'       -ModuleName 'MailboxFeatureService' -Times 1
            Should -Invoke 'Set-OnPremRemoteMailboxSafe' -ModuleName 'MailboxFeatureService' -Times 0
        }
    }

    Context 'UserMailbox (with Resolution)' {
        It 'routes to Set-OnPremMailboxSafe for UserMailbox resolution' {
            Mock -ModuleName 'MailboxFeatureService' Set-OnPremMailboxSafe       {}
            Mock -ModuleName 'MailboxFeatureService' Set-OnPremRemoteMailboxSafe {}

            $res = [pscustomobject]@{ RecipientTypeDetails = 'UserMailbox'; IsCloudOnly = $false }
            Set-MailboxVisibility -MailboxName 'gn-test' -Visibility 'Unhide' -WhatIfMode $false -Resolution $res

            Should -Invoke 'Set-OnPremMailboxSafe'       -ModuleName 'MailboxFeatureService' -Times 1
            Should -Invoke 'Set-OnPremRemoteMailboxSafe' -ModuleName 'MailboxFeatureService' -Times 0
        }
    }

    Context 'RemoteUserMailbox (with Resolution)' {
        It 'routes to Set-OnPremRemoteMailboxSafe for RemoteUserMailbox resolution' {
            Mock -ModuleName 'MailboxFeatureService' Set-OnPremMailboxSafe       {}
            Mock -ModuleName 'MailboxFeatureService' Set-OnPremRemoteMailboxSafe {}

            $res = [pscustomobject]@{ RecipientTypeDetails = 'RemoteUserMailbox'; IsCloudOnly = $false }
            Set-MailboxVisibility -MailboxName 'gn-test' -Visibility 'Hide' -WhatIfMode $false -Resolution $res

            Should -Invoke 'Set-OnPremRemoteMailboxSafe' -ModuleName 'MailboxFeatureService' -Times 1
            Should -Invoke 'Set-OnPremMailboxSafe'       -ModuleName 'MailboxFeatureService' -Times 0
        }
    }

    Context 'WhatIf mode' {
        It 'returns simulated result in WhatIf mode without calling real cmdlets (RemoteUserMailbox)' {
            $res = [pscustomobject]@{ RecipientTypeDetails = 'RemoteUserMailbox'; IsCloudOnly = $false }
            $result = Set-MailboxVisibility -MailboxName 'gn-test' -Visibility 'Hide' -WhatIfMode $true -Resolution $res
            $result.Simulated | Should -Be $true
            $result.Action    | Should -Be 'Set-RemoteMailbox'
        }
    }
}

# ---------------------------------------------------------------------------
# 3. UserProvisioningService.Enable-GenericUser — hybrid routing
# ---------------------------------------------------------------------------
Describe 'UserProvisioningService.Enable-GenericUser — hybrid routing' {

    Context 'WhatIf mode' {
        It 'returns simulated result without calling resolver or AD in WhatIf mode' {
            $ctx = New-TestContext -WhatIfMode $true
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext {}
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe {}

            $result = Enable-GenericUser -Context $ctx -Data (New-EnableRow)

            $result.Success   | Should -Be $true
            $result.Simulated | Should -Be $true
            $result.Action    | Should -Be 'EnableNonStdPersonMailbox'
            Should -Invoke 'Resolve-MailboxExecutionContext' -ModuleName 'UserProvisioningService' -Times 0
            Should -Invoke 'Get-AdUserBySamAccountNameSafe'  -ModuleName 'UserProvisioningService' -Times 0
        }
    }

    Context 'AD object not found' {
        It 'returns AD_OBJECT_NOT_FOUND when user does not exist in AD' {
            $ctx = New-TestContext
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe { $null }

            $result = Enable-GenericUser -Context $ctx -Data (New-EnableRow)

            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'AD_OBJECT_NOT_FOUND'
        }
    }

    Context 'On-Prem UserMailbox routing' {
        BeforeEach {
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe {
                New-MockAdUser -Sam 'gn-enable' -MailNickname 'gn-enable' -Enabled $false
            }
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecUserMailbox }
            Mock -ModuleName 'UserProvisioningService' Set-AdAccountPasswordSafe {}
            Mock -ModuleName 'UserProvisioningService' Enable-AdAccountSafe      {}
            Mock -ModuleName 'UserProvisioningService' Set-AdUserSafe            {}
            Mock -ModuleName 'UserProvisioningService' Set-MailboxVisibility     {}
        }

        It 'calls Enable-AdAccountSafe (on-prem AD) for UserMailbox' {
            $ctx = New-TestContext
            Enable-GenericUser -Context $ctx -Data (New-EnableRow) | Out-Null
            Should -Invoke 'Enable-AdAccountSafe' -ModuleName 'UserProvisioningService' -Times 1
        }

        It 'calls Set-MailboxVisibility (routes to On-Prem Set-Mailbox via FeatureService) for UserMailbox' {
            $ctx = New-TestContext
            Enable-GenericUser -Context $ctx -Data (New-EnableRow) | Out-Null
            Should -Invoke 'Set-MailboxVisibility' -ModuleName 'UserProvisioningService' -Times 1
        }

        It 'returns Success=true, Authority=OnPremExchange for UserMailbox' {
            $ctx = New-TestContext
            $result = Enable-GenericUser -Context $ctx -Data (New-EnableRow)
            $result.Success   | Should -Be $true
            $result.Authority | Should -Be 'OnPremExchange'
        }
    }

    Context 'RemoteUserMailbox routing — AD stays on-prem, features via Set-RemoteMailbox' {
        BeforeEach {
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe {
                New-MockAdUser -Sam 'gn-enable' -MailNickname 'gn-enable' -Enabled $false
            }
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecRemoteUser }
            Mock -ModuleName 'UserProvisioningService' Set-AdAccountPasswordSafe {}
            Mock -ModuleName 'UserProvisioningService' Enable-AdAccountSafe      {}
            Mock -ModuleName 'UserProvisioningService' Set-AdUserSafe            {}
            Mock -ModuleName 'UserProvisioningService' Set-MailboxVisibility     {}
        }

        It 'calls Enable-AdAccountSafe on-prem (AD activation never goes to EXO)' {
            $ctx = New-TestContext
            Enable-GenericUser -Context $ctx -Data (New-EnableRow) | Out-Null
            Should -Invoke 'Enable-AdAccountSafe' -ModuleName 'UserProvisioningService' -Times 1
        }

        It 'calls Set-MailboxVisibility (will route to Set-RemoteMailbox via FeatureService)' {
            $ctx = New-TestContext
            Enable-GenericUser -Context $ctx -Data (New-EnableRow) | Out-Null
            Should -Invoke 'Set-MailboxVisibility' -ModuleName 'UserProvisioningService' -Times 1
        }

        It 'returns Success=true, Authority=OnPremExchange for RemoteUserMailbox' {
            $ctx = New-TestContext
            $result = Enable-GenericUser -Context $ctx -Data (New-EnableRow)
            $result.Success   | Should -Be $true
            $result.Authority | Should -Be 'OnPremExchange'
        }
    }

    Context 'Cloud-only recipient' {
        It 'returns CLOUD_ONLY_NOT_SUPPORTED for EXO-only recipient' {
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe {
                New-MockAdUser -Sam 'gn-enable' -MailNickname 'gn-enable' -Enabled $false
            }
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecCloudOnly }

            $ctx = New-TestContext
            $result = Enable-GenericUser -Context $ctx -Data (New-EnableRow)
            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'CLOUD_ONLY_NOT_SUPPORTED'
        }
    }

    Context 'Migration transient — Retry' {
        It 'returns RequiresRetry=true and MAILBOX_MIGRATION_TRANSIENT' {
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe {
                New-MockAdUser -Sam 'gn-enable' -MailNickname 'gn-enable' -Enabled $false
            }
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecRetry }

            $ctx = New-TestContext
            $result = Enable-GenericUser -Context $ctx -Data (New-EnableRow)
            $result.RequiresRetry     | Should -Be $true
            $result.ErrorCode         | Should -Be 'MAILBOX_MIGRATION_TRANSIENT'
            $result.RetryAfterMinutes | Should -Be 15
        }
    }

    Context 'EXO required but disabled' {
        It 'returns EXO_REQUIRED_BUT_DISABLED when FeatureAuthority is ExchangeOnline but EXO disabled' {
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe {
                New-MockAdUser -Sam 'gn-enable' -MailNickname 'gn-enable' -Enabled $false
            }
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecExoDisabled }

            $ctx = New-TestContext
            $result = Enable-GenericUser -Context $ctx -Data (New-EnableRow)
            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'EXO_REQUIRED_BUT_DISABLED'
        }
    }

    Context 'User without mailbox (no mailNickname)' {
        It 'skips resolver and skips mailbox visibility for user without mailbox' {
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe {
                New-MockAdUser -Sam 'gn-enable' -MailNickname '' -Enabled $false
            }
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext {}
            Mock -ModuleName 'UserProvisioningService' Set-AdAccountPasswordSafe {}
            Mock -ModuleName 'UserProvisioningService' Enable-AdAccountSafe      {}
            Mock -ModuleName 'UserProvisioningService' Set-AdUserSafe            {}
            Mock -ModuleName 'UserProvisioningService' Set-MailboxVisibility     {}

            $ctx = New-TestContext
            $result = Enable-GenericUser -Context $ctx -Data (New-EnableRow)

            $result.Success | Should -Be $true
            Should -Invoke 'Resolve-MailboxExecutionContext' -ModuleName 'UserProvisioningService' -Times 0
            Should -Invoke 'Set-MailboxVisibility'           -ModuleName 'UserProvisioningService' -Times 0
        }
    }
}

# ---------------------------------------------------------------------------
# 4. UserProvisioningService.Disable-GenericUser — hybrid routing
# ---------------------------------------------------------------------------
Describe 'UserProvisioningService.Disable-GenericUser — hybrid routing' {

    Context 'WhatIf mode' {
        It 'returns simulated result without calling resolver or AD in WhatIf mode' {
            $ctx = New-TestContext -WhatIfMode $true
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext {}
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe {}

            $result = Disable-GenericUser -Context $ctx -Data (New-DisableRow)

            $result.Success   | Should -Be $true
            $result.Simulated | Should -Be $true
            $result.Action    | Should -Be 'DisableNonStdPersonMailbox'
            Should -Invoke 'Resolve-MailboxExecutionContext' -ModuleName 'UserProvisioningService' -Times 0
        }
    }

    Context 'AD object not found' {
        It 'returns AD_OBJECT_NOT_FOUND when user does not exist in AD' {
            $ctx = New-TestContext
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe { $null }

            $result = Disable-GenericUser -Context $ctx -Data (New-DisableRow)

            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'AD_OBJECT_NOT_FOUND'
        }
    }

    Context 'On-Prem UserMailbox routing' {
        BeforeEach {
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe {
                New-MockAdUser -Sam 'gn-disable' -MailNickname 'gn-disable' -Enabled $true
            }
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecUserMailbox }
            Mock -ModuleName 'UserProvisioningService' Disable-AdAccountSafe {}
            Mock -ModuleName 'UserProvisioningService' Set-AdUserSafe        {}
            Mock -ModuleName 'UserProvisioningService' Set-MailboxVisibility  {}
        }

        It 'calls Disable-AdAccountSafe (on-prem AD) for UserMailbox — AD deactivation never goes to EXO' {
            $ctx = New-TestContext
            Disable-GenericUser -Context $ctx -Data (New-DisableRow) | Out-Null
            Should -Invoke 'Disable-AdAccountSafe' -ModuleName 'UserProvisioningService' -Times 1
        }

        It 'calls Set-MailboxVisibility (routes to Set-Mailbox On-Prem via FeatureService) for UserMailbox' {
            $ctx = New-TestContext
            Disable-GenericUser -Context $ctx -Data (New-DisableRow) | Out-Null
            Should -Invoke 'Set-MailboxVisibility' -ModuleName 'UserProvisioningService' -Times 1
        }

        It 'returns Success=true, Authority=OnPremExchange for UserMailbox' {
            $ctx = New-TestContext
            $result = Disable-GenericUser -Context $ctx -Data (New-DisableRow)
            $result.Success   | Should -Be $true
            $result.Authority | Should -Be 'OnPremExchange'
        }
    }

    Context 'RemoteUserMailbox routing — AD stays on-prem' {
        BeforeEach {
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe {
                New-MockAdUser -Sam 'gn-disable' -MailNickname 'gn-disable' -Enabled $true
            }
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecRemoteUser }
            Mock -ModuleName 'UserProvisioningService' Disable-AdAccountSafe {}
            Mock -ModuleName 'UserProvisioningService' Set-AdUserSafe        {}
            Mock -ModuleName 'UserProvisioningService' Set-MailboxVisibility  {}
        }

        It 'calls Disable-AdAccountSafe on-prem for RemoteUserMailbox (AD deactivation is always on-prem)' {
            $ctx = New-TestContext
            Disable-GenericUser -Context $ctx -Data (New-DisableRow) | Out-Null
            Should -Invoke 'Disable-AdAccountSafe' -ModuleName 'UserProvisioningService' -Times 1
        }

        It 'returns Success=true, Authority=OnPremExchange for RemoteUserMailbox' {
            $ctx = New-TestContext
            $result = Disable-GenericUser -Context $ctx -Data (New-DisableRow)
            $result.Success   | Should -Be $true
            $result.Authority | Should -Be 'OnPremExchange'
        }
    }

    Context 'Cloud-only recipient' {
        It 'returns CLOUD_ONLY_NOT_SUPPORTED for EXO-only recipient' {
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe {
                New-MockAdUser -Sam 'gn-disable' -MailNickname 'gn-disable' -Enabled $true
            }
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecCloudOnly }

            $ctx = New-TestContext
            $result = Disable-GenericUser -Context $ctx -Data (New-DisableRow)
            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'CLOUD_ONLY_NOT_SUPPORTED'
        }
    }

    Context 'Migration transient — Retry' {
        It 'returns RequiresRetry=true and MAILBOX_MIGRATION_TRANSIENT for Retry state' {
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe {
                New-MockAdUser -Sam 'gn-disable' -MailNickname 'gn-disable' -Enabled $true
            }
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecRetry }

            $ctx = New-TestContext
            $result = Disable-GenericUser -Context $ctx -Data (New-DisableRow)
            $result.RequiresRetry     | Should -Be $true
            $result.ErrorCode         | Should -Be 'MAILBOX_MIGRATION_TRANSIENT'
            $result.RetryAfterMinutes | Should -Be 15
        }
    }

    Context 'EXO required but disabled' {
        It 'returns EXO_REQUIRED_BUT_DISABLED when FeatureAuthority=ExchangeOnline but EXO disabled' {
            Mock -ModuleName 'UserProvisioningService' Get-AdUserBySamAccountNameSafe {
                New-MockAdUser -Sam 'gn-disable' -MailNickname 'gn-disable' -Enabled $true
            }
            Mock -ModuleName 'UserProvisioningService' Resolve-MailboxExecutionContext { $script:ExecExoDisabled }

            $ctx = New-TestContext
            $result = Disable-GenericUser -Context $ctx -Data (New-DisableRow)
            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'EXO_REQUIRED_BUT_DISABLED'
        }
    }
}

# ---------------------------------------------------------------------------
# 5. Invoke-EnableGenericUser handler — RequiresRetry propagation
# ---------------------------------------------------------------------------
Describe 'Invoke-EnableGenericUser handler — RequiresRetry propagation and result handling' {

    Context 'RequiresRetry from service' {
        It 'returns JobResult.Status=Retry when service signals RequiresRetry=true' {
            $svc = @{
                UserProvisioning = [pscustomobject]@{
                    EnableUser = {
                        param($Ctx, $D)
                        [pscustomobject]@{
                            Success           = $false
                            RequiresRetry     = $true
                            RetryAfterMinutes = 15
                            Message           = 'Transient migration state.'
                            ErrorCode         = 'MAILBOX_MIGRATION_TRANSIENT'
                        }
                    }
                }
            }
            $ctx = New-TestContext -Payload @(New-EnableRow) -Services $svc
            $result = Invoke-EnableGenericUser -Context $ctx
            $result.Status | Should -Be 'Retry'
        }
    }

    Context 'Successful enable' {
        It 'returns Succeeded when service returns Success=true' {
            $svc = @{
                UserProvisioning = [pscustomobject]@{
                    EnableUser = {
                        param($Ctx, $D)
                        [pscustomobject]@{ Success = $true; RequiresRetry = $false; Message = 'Enabled.' }
                    }
                }
            }
            $ctx = New-TestContext -Payload @(New-EnableRow) -Services $svc
            $result = Invoke-EnableGenericUser -Context $ctx
            $result.Status | Should -Be 'Succeeded'
        }
    }

    Context 'Service failure' {
        It 'returns Failed when service returns Success=false (non-retry)' {
            $svc = @{
                UserProvisioning = [pscustomobject]@{
                    EnableUser = {
                        param($Ctx, $D)
                        [pscustomobject]@{ Success = $false; RequiresRetry = $false; Message = 'AD not found.'; ErrorCode = 'AD_OBJECT_NOT_FOUND' }
                    }
                }
            }
            $ctx = New-TestContext -Payload @(New-EnableRow) -Services $svc
            $result = Invoke-EnableGenericUser -Context $ctx
            $result.Status    | Should -Be 'Failed'
            $result.ErrorCode | Should -Be 'ENABLE_GENERIC_USER_FAILED'
        }
    }

    Context 'Validation failure' {
        It 'returns USECASE_ERROR when required CSV fields are missing' {
            $badRow = [pscustomobject]@{ ActionType = 'EnableNonStdPersonMailbox' }
            $ctx = New-TestContext -Payload @($badRow)
            $result = Invoke-EnableGenericUser -Context $ctx
            $result.Status    | Should -Be 'Failed'
            $result.ErrorCode | Should -Be 'USECASE_ERROR'
        }
    }
}

# ---------------------------------------------------------------------------
# 6. Invoke-DisableGenericUser handler — RequiresRetry propagation
# ---------------------------------------------------------------------------
Describe 'Invoke-DisableGenericUser handler — RequiresRetry propagation and result handling' {

    Context 'RequiresRetry from service' {
        It 'returns JobResult.Status=Retry when service signals RequiresRetry=true' {
            $svc = @{
                UserProvisioning = [pscustomobject]@{
                    DisableUser = {
                        param($Ctx, $D)
                        [pscustomobject]@{
                            Success           = $false
                            RequiresRetry     = $true
                            RetryAfterMinutes = 15
                            Message           = 'Transient migration state.'
                            ErrorCode         = 'MAILBOX_MIGRATION_TRANSIENT'
                        }
                    }
                }
            }
            $ctx = New-TestContext -Payload @(New-DisableRow) -Services $svc
            $result = Invoke-DisableGenericUser -Context $ctx
            $result.Status | Should -Be 'Retry'
        }
    }

    Context 'Successful disable' {
        It 'returns Succeeded when service returns Success=true' {
            $svc = @{
                UserProvisioning = [pscustomobject]@{
                    DisableUser = {
                        param($Ctx, $D)
                        [pscustomobject]@{ Success = $true; RequiresRetry = $false; Message = 'Disabled.' }
                    }
                }
            }
            $ctx = New-TestContext -Payload @(New-DisableRow) -Services $svc
            $result = Invoke-DisableGenericUser -Context $ctx
            $result.Status | Should -Be 'Succeeded'
        }
    }

    Context 'Service failure' {
        It 'returns Failed when service returns Success=false (non-retry)' {
            $svc = @{
                UserProvisioning = [pscustomobject]@{
                    DisableUser = {
                        param($Ctx, $D)
                        [pscustomobject]@{ Success = $false; RequiresRetry = $false; Message = 'AD not found.'; ErrorCode = 'AD_OBJECT_NOT_FOUND' }
                    }
                }
            }
            $ctx = New-TestContext -Payload @(New-DisableRow) -Services $svc
            $result = Invoke-DisableGenericUser -Context $ctx
            $result.Status    | Should -Be 'Failed'
            $result.ErrorCode | Should -Be 'DISABLE_GENERIC_USER_FAILED'
        }
    }

    Context 'Validation failure' {
        It 'returns USECASE_ERROR when required CSV fields are missing' {
            $badRow = [pscustomobject]@{ ActionType = 'DisableNonStdPersonMailbox' }
            $ctx = New-TestContext -Payload @($badRow)
            $result = Invoke-DisableGenericUser -Context $ctx
            $result.Status    | Should -Be 'Failed'
            $result.ErrorCode | Should -Be 'USECASE_ERROR'
        }
    }
}

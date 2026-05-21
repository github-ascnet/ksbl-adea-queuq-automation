Set-StrictMode -Version Latest

$root = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

Import-Module -Name (Join-Path $root 'core\JobResult.psm1')                               -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'core\Logging.psm1')                                 -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'core\Validation.psm1')                              -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnPremGateway.psm1')         -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnlineGateway.psm1')         -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'infrastructure\HybridMailboxResolver.psm1')         -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'shared\MailboxPermissionService.psm1')              -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'shared\GroupMailboxService.psm1')                   -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'usecases\GroupMailbox\AddGroupMailboxFmaMembers.psm1') -Force -DisableNameChecking

# ---------------------------------------------------------------------------
# Shared test infrastructure — helpers defined in BeforeAll for execution scope
# ---------------------------------------------------------------------------

BeforeAll {
    function New-TestLogger {
        [pscustomobject]@{
            RunId           = 'test-hybrid'
            LogFile         = (Join-Path $TestDrive 'hybrid.log')
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
            [bool]$ExoEnabled        = $false,
            [bool]$WhatIfMode        = $false,
            [scriptblock]$AddFmaMembers = $null
        )
        $fmaSvc = if ($AddFmaMembers) { $AddFmaMembers } else {
            { param($Context, $Data) [pscustomobject]@{ Success = $true; RequiresRetry = $false } }
        }
        [pscustomobject]@{
            Config     = (New-TestConfig -ExoEnabled $ExoEnabled)
            Logger     = (New-TestLogger)
            WhatIfMode = $WhatIfMode
            Services   = @{
                GroupMailbox = [pscustomobject]@{ AddFmaMembers = $fmaSvc }
            }
        }
    }

    function New-FmaRow {
        param(
            [string]$AdObjectName      = 'gmb-shared',
            [string]$FullAccessMembers = 'us001[ADD]',
            [string]$EnableSendAs      = 'True'
        )
        [pscustomobject]@{
            ActionType              = 'AddGroupMailboxFmaMembers'
            AdObjectName            = $AdObjectName
            FullAccessMembers       = $FullAccessMembers
            EnableSendAs            = $EnableSendAs
            CurrentUserName         = 'Tester'
            CurrentUserDomainName   = 'DOMAIN'
            CurrentUserEMailAddress = 'tester@example.org'
        }
    }

    # Preset execution-context objects used in MockWith blocks for MailboxPermissionService tests
    $script:ExecOnPrem = [pscustomobject]@{
        Identity = 'gmb-shared'; ExistsOnPrem = $true; ExistsInExchangeOnline = $false
        RecipientTypeDetails = 'SharedMailbox'; AttributeAuthority = 'OnPremAD'
        MailboxAuthority = 'OnPremExchange'; PermissionAuthority = 'OnPremExchange'
        IsMigrationTransient = $false; RecommendedAction = 'Execute'; RetryAfterMinutes = 15
        Reason = 'On-prem SharedMailbox found.'
    }
    $script:ExecEXO = [pscustomobject]@{
        Identity = 'gmb-shared'; ExistsOnPrem = $true; ExistsInExchangeOnline = $true
        RecipientTypeDetails = 'RemoteSharedMailbox'; AttributeAuthority = 'OnPremAD'
        MailboxAuthority = 'ExchangeOnline'; PermissionAuthority = 'ExchangeOnline'
        IsMigrationTransient = $false; RecommendedAction = 'Execute'; RetryAfterMinutes = 15
        Reason = 'RemoteSharedMailbox confirmed in EXO.'
    }
    $script:ExecRetry = [pscustomobject]@{
        Identity = 'gmb-shared'; ExistsOnPrem = $true; ExistsInExchangeOnline = $false
        RecipientTypeDetails = 'RemoteSharedMailbox'; AttributeAuthority = 'OnPremAD'
        MailboxAuthority = 'OnPremExchange'; PermissionAuthority = 'ExchangeOnline'
        IsMigrationTransient = $true; RecommendedAction = 'Retry'; RetryAfterMinutes = 15
        Reason = 'Transient migration sync state.'
    }
    $script:ExecFailExoDisabled = [pscustomobject]@{
        Identity = 'gmb-shared'; ExistsOnPrem = $true; ExistsInExchangeOnline = $false
        RecipientTypeDetails = 'RemoteSharedMailbox'; AttributeAuthority = 'OnPremAD'
        MailboxAuthority = 'OnPremExchange'; PermissionAuthority = 'ExchangeOnline'
        IsMigrationTransient = $false; RecommendedAction = 'Fail'; RetryAfterMinutes = 15
        Reason = 'RemoteSharedMailbox found but EXO is disabled.'
    }
    $script:ExecFailNotFound = [pscustomobject]@{
        Identity = 'gmb-missing'; ExistsOnPrem = $false; ExistsInExchangeOnline = $false
        RecipientTypeDetails = $null; AttributeAuthority = 'ExchangeOnline'
        MailboxAuthority = 'Unknown'; PermissionAuthority = 'Unknown'
        IsMigrationTransient = $false; RecommendedAction = 'Fail'; RetryAfterMinutes = 15
        Reason = 'Identity not found on-prem or in EXO.'
    }
}

# ---------------------------------------------------------------------------
# HybridMailboxResolver — unit tests
# ---------------------------------------------------------------------------

Describe 'HybridMailboxResolver.Resolve-MailboxExecutionContext' {

    Context 'On-Prem SharedMailbox (EXO disabled)' {
        It 'returns OnPremExchange authority with Execute action' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'SharedMailbox' }
            }
            $config = @{ ExchangeOnline = @{ Enabled = $false } }
            $result = Resolve-MailboxExecutionContext -Identity 'gmb-test' -Config $config
            $result.PermissionAuthority  | Should -Be 'OnPremExchange'
            $result.RecommendedAction    | Should -Be 'Execute'
            $result.IsMigrationTransient | Should -Be $false
        }
    }

    Context 'RemoteSharedMailbox — EXO enabled and EXO mailbox found' {
        It 'returns ExchangeOnline authority with Execute action' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'RemoteSharedMailbox' }
            }
            Mock -ModuleName 'HybridMailboxResolver' Get-ExoRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'UserMailbox' }
            }
            $config = @{ ExchangeOnline = @{ Enabled = $true; AppId = 'x'; CertThumbprint = 'x'; Organization = 'x'; TenantDomain = 'x' } }
            $result = Resolve-MailboxExecutionContext -Identity 'gmb-test' -Config $config
            $result.PermissionAuthority    | Should -Be 'ExchangeOnline'
            $result.RecommendedAction      | Should -Be 'Execute'
            $result.IsMigrationTransient   | Should -Be $false
            $result.ExistsInExchangeOnline | Should -Be $true
        }
    }

    Context 'RemoteSharedMailbox — EXO enabled but EXO mailbox not yet visible (transient)' {
        It 'returns ExchangeOnline authority with Retry action and IsMigrationTransient true' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'RemoteSharedMailbox' }
            }
            Mock -ModuleName 'HybridMailboxResolver' Get-ExoRecipientSafe { $null }
            $config = @{ ExchangeOnline = @{ Enabled = $true; AppId = 'x'; CertThumbprint = 'x'; Organization = 'x'; TenantDomain = 'x' } }
            $result = Resolve-MailboxExecutionContext -Identity 'gmb-test' -Config $config
            $result.PermissionAuthority  | Should -Be 'ExchangeOnline'
            $result.RecommendedAction    | Should -Be 'Retry'
            $result.IsMigrationTransient | Should -Be $true
            $result.RetryAfterMinutes    | Should -Be 15
        }
    }

    Context 'RemoteSharedMailbox — EXO disabled' {
        It 'returns ExchangeOnline authority with Fail action' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'RemoteSharedMailbox' }
            }
            $config = @{ ExchangeOnline = @{ Enabled = $false } }
            $result = Resolve-MailboxExecutionContext -Identity 'gmb-test' -Config $config
            $result.PermissionAuthority | Should -Be 'ExchangeOnline'
            $result.RecommendedAction   | Should -Be 'Fail'
        }
    }

    Context 'Not found anywhere' {
        It 'returns Unknown authority with Fail action' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe { $null }
            Mock -ModuleName 'HybridMailboxResolver' Get-ExoRecipientSafe    { $null }
            $config = @{ ExchangeOnline = @{ Enabled = $true; AppId = 'x'; CertThumbprint = 'x'; Organization = 'x'; TenantDomain = 'x' } }
            $result = Resolve-MailboxExecutionContext -Identity 'missing' -Config $config
            $result.PermissionAuthority | Should -Be 'Unknown'
            $result.RecommendedAction   | Should -Be 'Fail'
        }
    }

    Context 'EXO-only mailbox (no on-prem object)' {
        It 'returns ExchangeOnline authority with Execute action' {
            Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe { $null }
            Mock -ModuleName 'HybridMailboxResolver' Get-ExoRecipientSafe {
                [pscustomobject]@{ RecipientTypeDetails = 'UserMailbox' }
            }
            $config = @{ ExchangeOnline = @{ Enabled = $true; AppId = 'x'; CertThumbprint = 'x'; Organization = 'x'; TenantDomain = 'x' } }
            $result = Resolve-MailboxExecutionContext -Identity 'cloud-only' -Config $config
            $result.PermissionAuthority    | Should -Be 'ExchangeOnline'
            $result.RecommendedAction      | Should -Be 'Execute'
            $result.ExistsOnPrem           | Should -Be $false
            $result.ExistsInExchangeOnline | Should -Be $true
        }
    }
}

# ---------------------------------------------------------------------------
# MailboxPermissionService — unit tests
# ---------------------------------------------------------------------------

Describe 'MailboxPermissionService.Add-MailboxFullAccess' {

    Context 'On-Prem SharedMailbox routing' {
        It 'calls Add-OnPremMailboxPermissionSafe and returns Success=$true' {
            $snap = $script:ExecOnPrem
            Mock -ModuleName 'MailboxPermissionService' Resolve-MailboxExecutionContext { $snap }
            Mock -ModuleName 'MailboxPermissionService' Add-OnPremMailboxPermissionSafe { }
            $context = New-TestContext
            $result = Add-MailboxFullAccess -Context $context -MailboxIdentity 'gmb-shared' -Trustee 'us001'
            $result.Success   | Should -Be $true
            $result.Changed   | Should -Be $true
            $result.Authority | Should -Be 'OnPremExchange'
            $result.Operation | Should -Be 'FullAccess-Add'
            Should -Invoke Add-OnPremMailboxPermissionSafe -ModuleName 'MailboxPermissionService' -Times 1
        }
    }

    Context 'Exchange Online routing (RemoteSharedMailbox)' {
        It 'calls Add-ExoMailboxPermissionSafe and returns Success=$true' {
            $snap = $script:ExecEXO
            Mock -ModuleName 'MailboxPermissionService' Resolve-MailboxExecutionContext { $snap }
            Mock -ModuleName 'MailboxPermissionService' Add-ExoMailboxPermissionSafe { }
            Mock -ModuleName 'MailboxPermissionService' Add-OnPremMailboxPermissionSafe { throw 'Should not be called for EXO mailbox' }
            $context = New-TestContext -ExoEnabled $true
            $result = Add-MailboxFullAccess -Context $context -MailboxIdentity 'gmb-shared' -Trustee 'us001'
            $result.Success   | Should -Be $true
            $result.Changed   | Should -Be $true
            $result.Authority | Should -Be 'ExchangeOnline'
            Should -Invoke Add-ExoMailboxPermissionSafe    -ModuleName 'MailboxPermissionService' -Times 1
            Should -Invoke Add-OnPremMailboxPermissionSafe -ModuleName 'MailboxPermissionService' -Times 0 -Exactly
        }
    }

    Context 'Transient migration state (Retry)' {
        It 'returns RequiresRetry=$true without calling any gateway' {
            $snap = $script:ExecRetry
            Mock -ModuleName 'MailboxPermissionService' Resolve-MailboxExecutionContext { $snap }
            Mock -ModuleName 'MailboxPermissionService' Add-OnPremMailboxPermissionSafe { }
            Mock -ModuleName 'MailboxPermissionService' Add-ExoMailboxPermissionSafe { }
            $context = New-TestContext -ExoEnabled $true
            $result = Add-MailboxFullAccess -Context $context -MailboxIdentity 'gmb-shared' -Trustee 'us001'
            $result.Success           | Should -Be $false
            $result.RequiresRetry     | Should -Be $true
            $result.RetryAfterMinutes | Should -Be 15
            $result.ErrorCode         | Should -Be 'MAILBOX_MIGRATION_TRANSIENT'
            Should -Invoke Add-OnPremMailboxPermissionSafe -ModuleName 'MailboxPermissionService' -Times 0 -Exactly
            Should -Invoke Add-ExoMailboxPermissionSafe    -ModuleName 'MailboxPermissionService' -Times 0 -Exactly
        }
    }

    Context 'EXO required but disabled (Fail)' {
        It 'returns Success=$false and ErrorCode=EXO_REQUIRED_BUT_DISABLED' {
            $snap = $script:ExecFailExoDisabled
            Mock -ModuleName 'MailboxPermissionService' Resolve-MailboxExecutionContext { $snap }
            $context = New-TestContext -ExoEnabled $false
            $result = Add-MailboxFullAccess -Context $context -MailboxIdentity 'gmb-shared' -Trustee 'us001'
            $result.Success       | Should -Be $false
            $result.RequiresRetry | Should -Be $false
            $result.ErrorCode     | Should -Be 'EXO_REQUIRED_BUT_DISABLED'
        }
    }

    Context 'Mailbox not found (Fail, Unknown authority)' {
        It 'returns Success=$false and ErrorCode=MAILBOX_NOT_FOUND' {
            $snap = $script:ExecFailNotFound
            Mock -ModuleName 'MailboxPermissionService' Resolve-MailboxExecutionContext { $snap }
            $context = New-TestContext
            $result = Add-MailboxFullAccess -Context $context -MailboxIdentity 'gmb-missing' -Trustee 'us001'
            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'MAILBOX_NOT_FOUND'
        }
    }

    Context 'Gateway exception' {
        It 'catches the exception and returns Success=$false with ErrorCode=GATEWAY_ERROR' {
            $snap = $script:ExecOnPrem
            Mock -ModuleName 'MailboxPermissionService' Resolve-MailboxExecutionContext { $snap }
            Mock -ModuleName 'MailboxPermissionService' Add-OnPremMailboxPermissionSafe { throw 'Exchange connection failed' }
            $context = New-TestContext
            $result = Add-MailboxFullAccess -Context $context -MailboxIdentity 'gmb-shared' -Trustee 'us001'
            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'GATEWAY_ERROR'
            $result.Message   | Should -Match 'Exchange connection failed'
        }
    }
}

Describe 'MailboxPermissionService.Add-MailboxSendAs' {

    Context 'On-Prem routing' {
        It 'calls Add-OnPremSendAsPermissionSafe and returns Success=$true' {
            $snap = $script:ExecOnPrem
            Mock -ModuleName 'MailboxPermissionService' Resolve-MailboxExecutionContext { $snap }
            Mock -ModuleName 'MailboxPermissionService' Add-OnPremSendAsPermissionSafe { }
            $context = New-TestContext
            $result = Add-MailboxSendAs -Context $context -MailboxIdentity 'gmb-shared' -Trustee 'us001'
            $result.Success   | Should -Be $true
            $result.Operation | Should -Be 'SendAs-Add'
            Should -Invoke Add-OnPremSendAsPermissionSafe -ModuleName 'MailboxPermissionService' -Times 1
        }
    }

    Context 'Exchange Online routing' {
        It 'calls Add-ExoSendAsPermissionSafe and returns Success=$true' {
            $snap = $script:ExecEXO
            Mock -ModuleName 'MailboxPermissionService' Resolve-MailboxExecutionContext { $snap }
            Mock -ModuleName 'MailboxPermissionService' Add-ExoSendAsPermissionSafe { }
            $context = New-TestContext -ExoEnabled $true
            $result = Add-MailboxSendAs -Context $context -MailboxIdentity 'gmb-shared' -Trustee 'us001'
            $result.Success   | Should -Be $true
            $result.Authority | Should -Be 'ExchangeOnline'
            Should -Invoke Add-ExoSendAsPermissionSafe -ModuleName 'MailboxPermissionService' -Times 1
        }
    }
}

Describe 'MailboxPermissionService.Remove-MailboxFullAccess' {

    Context 'On-Prem routing' {
        It 'calls Remove-OnPremMailboxPermissionSafe and returns Success=$true' {
            $snap = $script:ExecOnPrem
            Mock -ModuleName 'MailboxPermissionService' Resolve-MailboxExecutionContext { $snap }
            Mock -ModuleName 'MailboxPermissionService' Remove-OnPremMailboxPermissionSafe { }
            $context = New-TestContext
            $result = Remove-MailboxFullAccess -Context $context -MailboxIdentity 'gmb-shared' -Trustee 'us001'
            $result.Success   | Should -Be $true
            $result.Operation | Should -Be 'FullAccess-Remove'
            Should -Invoke Remove-OnPremMailboxPermissionSafe -ModuleName 'MailboxPermissionService' -Times 1
        }
    }

    Context 'Exchange Online routing' {
        It 'calls Remove-ExoMailboxPermissionSafe and returns Success=$true' {
            $snap = $script:ExecEXO
            Mock -ModuleName 'MailboxPermissionService' Resolve-MailboxExecutionContext { $snap }
            Mock -ModuleName 'MailboxPermissionService' Remove-ExoMailboxPermissionSafe { }
            $context = New-TestContext -ExoEnabled $true
            $result = Remove-MailboxFullAccess -Context $context -MailboxIdentity 'gmb-shared' -Trustee 'us001'
            $result.Success   | Should -Be $true
            $result.Authority | Should -Be 'ExchangeOnline'
            Should -Invoke Remove-ExoMailboxPermissionSafe -ModuleName 'MailboxPermissionService' -Times 1
        }
    }
}

# ---------------------------------------------------------------------------
# GroupMailboxService.Add-GroupMailboxFmaMembers — unit tests
# ---------------------------------------------------------------------------

Describe 'GroupMailboxService.Add-GroupMailboxFmaMembers' {

    Context 'WhatIf mode' {
        It 'returns simulated result without calling any permission service function' {
            Mock -ModuleName 'GroupMailboxService' Add-MailboxFullAccess { throw 'Should not be called in WhatIf' }
            $context = New-TestContext -WhatIfMode $true
            $result = Add-GroupMailboxFmaMembers -Context $context -Data (New-FmaRow -FullAccessMembers 'us001[ADD]!us002[DEL]')
            $result.Success         | Should -Be $true
            $result.Simulated       | Should -Be $true
            $result.RequiresRetry   | Should -Be $false
            $result.Authority       | Should -Be 'WhatIf'
            $result.FullAccessCount | Should -Be 2
            Should -Invoke Add-MailboxFullAccess -ModuleName 'GroupMailboxService' -Times 0 -Exactly
        }
    }

    Context 'On-Prem SharedMailbox — ADD token with SendAs' {
        It 'calls Add-MailboxFullAccess and Add-MailboxSendAs once each, returns Success=$true' {
            Mock -ModuleName 'GroupMailboxService' Add-MailboxFullAccess {
                [pscustomobject]@{ Success = $true; Changed = $true; RequiresRetry = $false; RetryAfterMinutes = 0; Authority = 'OnPremExchange'; ErrorCode = $null; Message = 'ok' }
            }
            Mock -ModuleName 'GroupMailboxService' Add-MailboxSendAs {
                [pscustomobject]@{ Success = $true; Changed = $true; RequiresRetry = $false; RetryAfterMinutes = 0; Authority = 'OnPremExchange'; ErrorCode = $null; Message = 'ok' }
            }
            $context = New-TestContext
            $result = Add-GroupMailboxFmaMembers -Context $context -Data (New-FmaRow -FullAccessMembers 'us001[ADD]' -EnableSendAs 'True')
            $result.Success         | Should -Be $true
            $result.FullAccessCount | Should -Be 1
            $result.SendAsCount     | Should -Be 1
            $result.Authority       | Should -Be 'OnPremExchange'
            $result.FailedMembers.Count | Should -Be 0
            Should -Invoke Add-MailboxFullAccess -ModuleName 'GroupMailboxService' -Times 1
            Should -Invoke Add-MailboxSendAs    -ModuleName 'GroupMailboxService' -Times 1
        }
    }

    Context 'Exchange Online routing — ADD token' {
        It 'succeeds with ExchangeOnline authority' {
            Mock -ModuleName 'GroupMailboxService' Add-MailboxFullAccess {
                [pscustomobject]@{ Success = $true; Changed = $true; RequiresRetry = $false; RetryAfterMinutes = 0; Authority = 'ExchangeOnline'; ErrorCode = $null; Message = 'ok' }
            }
            Mock -ModuleName 'GroupMailboxService' Add-MailboxSendAs {
                [pscustomobject]@{ Success = $true; Changed = $true; RequiresRetry = $false; RetryAfterMinutes = 0; Authority = 'ExchangeOnline'; ErrorCode = $null; Message = 'ok' }
            }
            $context = New-TestContext -ExoEnabled $true
            $result = Add-GroupMailboxFmaMembers -Context $context -Data (New-FmaRow -FullAccessMembers 'us001[ADD]' -EnableSendAs 'True')
            $result.Success   | Should -Be $true
            $result.Authority | Should -Be 'ExchangeOnline'
        }
    }

    Context 'DEL token with SendAs' {
        It 'calls Remove-MailboxFullAccess and Remove-MailboxSendAs once each' {
            Mock -ModuleName 'GroupMailboxService' Remove-MailboxFullAccess {
                [pscustomobject]@{ Success = $true; Changed = $true; RequiresRetry = $false; RetryAfterMinutes = 0; Authority = 'OnPremExchange'; ErrorCode = $null; Message = 'ok' }
            }
            Mock -ModuleName 'GroupMailboxService' Remove-MailboxSendAs {
                [pscustomobject]@{ Success = $true; Changed = $true; RequiresRetry = $false; RetryAfterMinutes = 0; Authority = 'OnPremExchange'; ErrorCode = $null; Message = 'ok' }
            }
            $context = New-TestContext
            $result = Add-GroupMailboxFmaMembers -Context $context -Data (New-FmaRow -FullAccessMembers 'us001[DEL]' -EnableSendAs 'True')
            $result.Success         | Should -Be $true
            $result.FullAccessCount | Should -Be 1
            $result.SendAsCount     | Should -Be 1
            Should -Invoke Remove-MailboxFullAccess -ModuleName 'GroupMailboxService' -Times 1
            Should -Invoke Remove-MailboxSendAs     -ModuleName 'GroupMailboxService' -Times 1
        }
    }

    Context 'SendAs disabled — ADD token' {
        It 'calls Add-MailboxFullAccess but not Add-MailboxSendAs' {
            Mock -ModuleName 'GroupMailboxService' Add-MailboxFullAccess {
                [pscustomobject]@{ Success = $true; Changed = $true; RequiresRetry = $false; RetryAfterMinutes = 0; Authority = 'OnPremExchange'; ErrorCode = $null; Message = 'ok' }
            }
            Mock -ModuleName 'GroupMailboxService' Add-MailboxSendAs { throw 'Should not be called when SendAs disabled' }
            $context = New-TestContext
            $result = Add-GroupMailboxFmaMembers -Context $context -Data (New-FmaRow -FullAccessMembers 'us001[ADD]' -EnableSendAs 'False')
            $result.Success     | Should -Be $true
            $result.SendAsCount | Should -Be 0
            Should -Invoke Add-MailboxSendAs -ModuleName 'GroupMailboxService' -Times 0 -Exactly
        }
    }

    Context 'Transient migration state — RequiresRetry propagation' {
        It 'returns RequiresRetry=$true immediately when FullAccess returns retry' {
            Mock -ModuleName 'GroupMailboxService' Add-MailboxFullAccess {
                [pscustomobject]@{ Success = $false; Changed = $false; RequiresRetry = $true; RetryAfterMinutes = 15; Authority = 'ExchangeOnline'; ErrorCode = 'MAILBOX_MIGRATION_TRANSIENT'; Message = 'Transient.' }
            }
            $context = New-TestContext -ExoEnabled $true
            $result = Add-GroupMailboxFmaMembers -Context $context -Data (New-FmaRow -FullAccessMembers 'us001[ADD]')
            $result.Success           | Should -Be $false
            $result.RequiresRetry     | Should -Be $true
            $result.RetryAfterMinutes | Should -Be 15
            $result.ErrorCode         | Should -Be 'MAILBOX_MIGRATION_TRANSIENT'
        }
    }

    Context 'Partial failure — one member fails, another succeeds' {
        It 'returns Success=$false with FailedMembers list' {
            $callCount = 0
            Mock -ModuleName 'GroupMailboxService' Add-MailboxFullAccess {
                $script:partialCallCount++
                if ($script:partialCallCount -eq 1) {
                    [pscustomobject]@{ Success = $true;  Changed = $true;  RequiresRetry = $false; RetryAfterMinutes = 0; Authority = 'OnPremExchange'; ErrorCode = $null;              Message = 'ok'        }
                } else {
                    [pscustomobject]@{ Success = $false; Changed = $false; RequiresRetry = $false; RetryAfterMinutes = 0; Authority = 'Unknown';       ErrorCode = 'MAILBOX_NOT_FOUND'; Message = 'not found' }
                }
            }
            $script:partialCallCount = 0
            $context = New-TestContext
            $result = Add-GroupMailboxFmaMembers -Context $context -Data (New-FmaRow -FullAccessMembers 'us001[ADD]!us002[ADD]' -EnableSendAs 'False')
            $result.Success         | Should -Be $false
            $result.FullAccessCount | Should -Be 1
            $result.ErrorCode       | Should -Be 'GROUP_MAILBOX_PERMISSION_PARTIAL_FAILURE'
            $result.FailedMembers   | Should -Contain 'us002'
        }
    }
}

# ---------------------------------------------------------------------------
# Handler Invoke-AddGroupMailboxFmaMembers — RequiresRetry → JobRetryResult
# ---------------------------------------------------------------------------

Describe 'Invoke-AddGroupMailboxFmaMembers handler — RequiresRetry propagation' {

    It 'returns Retry status when service returns RequiresRetry=$true' {
        $context = New-TestContext -AddFmaMembers {
            param($Context, $Data)
            [pscustomobject]@{
                Success           = $false
                RequiresRetry     = $true
                RetryAfterMinutes = 15
                AdObjectName      = $Data.AdObjectName
                ErrorCode         = 'MAILBOX_MIGRATION_TRANSIENT'
                Message           = 'Transient migration state.'
            }
        }
        $context | Add-Member -MemberType NoteProperty -Name 'Payload' -Value @(New-FmaRow)
        $result = Invoke-AddGroupMailboxFmaMembers -Context $context
        $result.Status  | Should -Be 'Retry'
        $result.Message | Should -Match 'transient migration state'
    }

    It 'returns Succeeded status when service returns Success=$true' {
        $context = New-TestContext -AddFmaMembers {
            param($Context, $Data)
            [pscustomobject]@{ Success = $true; RequiresRetry = $false; Message = 'All done.' }
        }
        $context | Add-Member -MemberType NoteProperty -Name 'Payload' -Value @(New-FmaRow)
        $result = Invoke-AddGroupMailboxFmaMembers -Context $context
        $result.Status | Should -Be 'Succeeded'
    }

    It 'returns Failed status when service returns Success=$false (no retry)' {
        $context = New-TestContext -AddFmaMembers {
            param($Context, $Data)
            [pscustomobject]@{ Success = $false; RequiresRetry = $false; ErrorCode = 'MAILBOX_NOT_FOUND'; Message = 'Mailbox not found.' }
        }
        $context | Add-Member -MemberType NoteProperty -Name 'Payload' -Value @(New-FmaRow)
        $result = Invoke-AddGroupMailboxFmaMembers -Context $context
        $result.Status | Should -Be 'Failed'
    }
}

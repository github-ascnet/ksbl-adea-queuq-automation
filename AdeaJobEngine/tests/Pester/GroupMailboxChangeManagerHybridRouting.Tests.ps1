Set-StrictMode -Version Latest

$root = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

Import-Module -Name (Join-Path $root 'core\JobResult.psm1')                                    -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'core\Logging.psm1')                                      -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'core\Validation.psm1')                                   -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnPremGateway.psm1')              -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'infrastructure\ActiveDirectoryGateway.psm1')             -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnlineGateway.psm1')              -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'infrastructure\HybridMailboxResolver.psm1')              -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'shared\GroupMailboxService.psm1')                        -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'usecases\GroupMailbox\ChangeManagerGroupMailbox.psm1')   -Force -DisableNameChecking

# ---------------------------------------------------------------------------
# Shared test infrastructure — all helpers in BeforeAll for execution scope
# ---------------------------------------------------------------------------
BeforeAll {
    function New-TestLogger {
        [pscustomobject]@{
            RunId           = 'test-cm-hybrid'
            LogFile         = (Join-Path $TestDrive 'cm-hybrid.log')
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
                Enabled               = $ExoEnabled
                AppId                 = 'test-app-id'
                CertificateThumbprint = 'test-cert'
                Organization          = 'test.onmicrosoft.com'
                TenantDomain          = 'test.onmicrosoft.com'
            }
        }
    }

    function New-TestContext {
        param(
            [bool]$ExoEnabled        = $false,
            [bool]$WhatIfMode        = $false,
            [scriptblock]$ChangeManager = $null
        )
        $cmSvc = if ($ChangeManager) { $ChangeManager } else {
            { param($Context, $Data) [pscustomobject]@{ Success = $true; RequiresRetry = $false } }
        }
        [pscustomobject]@{
            Config     = (New-TestConfig -ExoEnabled $ExoEnabled)
            Logger     = (New-TestLogger)
            WhatIfMode = $WhatIfMode
            Services   = @{
                GroupMailbox = [pscustomobject]@{ ChangeManager = $cmSvc }
            }
        }
    }

    function New-CmRow {
        param(
            [string]$AdObjectName        = 'gmb-it',
            [string]$ManagerAdObjectName = 'us001'
        )
        [pscustomobject]@{
            ActionType              = 'ChangeManager'
            AdObjectName            = $AdObjectName
            ManagerAdObjectName     = $ManagerAdObjectName
            CurrentUserName         = 'testuser'
            CurrentUserDomainName   = 'TESTDOMAIN'
            CurrentUserEMailAddress = 'testuser@example.test'
        }
    }

    # Pre-built execution context snapshots — used in MockWith blocks
    # (must be $script: scope so they are reachable from MockWith scriptblocks)
    $script:ExecOnPrem = [pscustomobject]@{
        Identity               = 'gmb-it'
        ExistsOnPrem           = $true
        ExistsInExchangeOnline = $false
        RecipientTypeDetails   = 'SharedMailbox'
        AttributeAuthority     = 'OnPremAD'
        MailboxAuthority       = 'OnPremExchange'
        ManagementAuthority    = 'OnPremExchange'
        PermissionAuthority    = 'OnPremExchange'
        IsMigrationTransient   = $false
        RecommendedAction      = 'Execute'
        RetryAfterMinutes      = 15
        Reason                 = 'On-prem SharedMailbox found.'
    }

    $script:ExecEXO = [pscustomobject]@{
        Identity               = 'gmb-it'
        ExistsOnPrem           = $true
        ExistsInExchangeOnline = $true
        RecipientTypeDetails   = 'RemoteSharedMailbox'
        AttributeAuthority     = 'OnPremAD'
        MailboxAuthority       = 'ExchangeOnline'
        ManagementAuthority    = 'ExchangeOnline'
        PermissionAuthority    = 'ExchangeOnline'
        IsMigrationTransient   = $false
        RecommendedAction      = 'Execute'
        RetryAfterMinutes      = 15
        Reason                 = 'RemoteSharedMailbox confirmed in Exchange Online.'
    }

    $script:ExecRetry = [pscustomobject]@{
        Identity               = 'gmb-it'
        ExistsOnPrem           = $true
        ExistsInExchangeOnline = $false
        RecipientTypeDetails   = 'RemoteSharedMailbox'
        AttributeAuthority     = 'OnPremAD'
        MailboxAuthority       = 'ExchangeOnline'
        ManagementAuthority    = 'ExchangeOnline'
        PermissionAuthority    = 'ExchangeOnline'
        IsMigrationTransient   = $true
        RecommendedAction      = 'Retry'
        RetryAfterMinutes      = 15
        Reason                 = 'RemoteSharedMailbox found on-prem but EXO mailbox not yet visible.'
    }

    $script:ExecFailExoDisabled = [pscustomobject]@{
        Identity               = 'gmb-it'
        ExistsOnPrem           = $true
        ExistsInExchangeOnline = $false
        RecipientTypeDetails   = 'RemoteSharedMailbox'
        AttributeAuthority     = 'OnPremAD'
        MailboxAuthority       = 'ExchangeOnline'
        ManagementAuthority    = 'ExchangeOnline'
        PermissionAuthority    = 'ExchangeOnline'
        IsMigrationTransient   = $false
        RecommendedAction      = 'Fail'
        RetryAfterMinutes      = 15
        Reason                 = 'RemoteSharedMailbox found on-prem but Exchange Online is disabled by configuration.'
    }

    $script:ExecFailNotFound = [pscustomobject]@{
        Identity               = 'gmb-it'
        ExistsOnPrem           = $false
        ExistsInExchangeOnline = $false
        RecipientTypeDetails   = $null
        AttributeAuthority     = 'ExchangeOnline'
        MailboxAuthority       = 'Unknown'
        ManagementAuthority    = 'Unknown'
        PermissionAuthority    = 'Unknown'
        IsMigrationTransient   = $false
        RecommendedAction      = 'Fail'
        RetryAfterMinutes      = 15
        Reason                 = "Identity 'gmb-it' not found on-prem or in Exchange Online."
    }
}

# ---------------------------------------------------------------------------
# GroupMailboxService.Set-GroupMailboxManager — hybrid routing
# ---------------------------------------------------------------------------
Describe 'GroupMailboxService.Set-GroupMailboxManager' {

    Context 'WhatIf mode' {
        It 'returns simulated result without calling resolver or any Exchange/AD cmdlets' {
            Mock -ModuleName 'GroupMailboxService' Resolve-MailboxExecutionContext { throw 'Should not be called in WhatIf' }
            Mock -ModuleName 'GroupMailboxService' Invoke-LegacyMailboxPermissionMutation { throw 'Should not be called in WhatIf' }
            Mock -ModuleName 'GroupMailboxService' Add-ExoMailboxPermissionSafe { throw 'Should not be called in WhatIf' }
            Mock -ModuleName 'GroupMailboxService' Set-AdUserSafe { throw 'Should not be called in WhatIf' }

            $ctx = New-TestContext -WhatIfMode $true
            $row = New-CmRow
            $result = Set-GroupMailboxManager -Context $ctx -Data $row

            $result.Success   | Should -Be $true
            $result.Simulated | Should -Be $true
            $result.Authority | Should -Be 'WhatIf'
        }
    }

    Context 'On-Prem SharedMailbox routing' {
        It 'calls Invoke-LegacyMailboxPermissionMutation and Set-AdUserSafe; returns Success=$true' {
            $snap = $script:ExecOnPrem
            Mock -ModuleName 'GroupMailboxService' Resolve-MailboxExecutionContext { $snap }
            Mock -ModuleName 'GroupMailboxService' Invoke-LegacyMailboxPermissionMutation { @() }
            Mock -ModuleName 'GroupMailboxService' Set-AdUserSafe { }
            Mock -ModuleName 'GroupMailboxService' Add-ExoMailboxPermissionSafe { throw 'EXO should not be called for On-Prem mailbox' }

            $ctx = New-TestContext
            $row = New-CmRow
            $result = Set-GroupMailboxManager -Context $ctx -Data $row

            $result.Success   | Should -Be $true
            $result.Changed   | Should -Be $true
            $result.Authority | Should -Be 'OnPremExchange'
            Should -Invoke Invoke-LegacyMailboxPermissionMutation -ModuleName 'GroupMailboxService' -Times 1
            Should -Invoke Set-AdUserSafe                         -ModuleName 'GroupMailboxService' -Times 1
        }
    }

    Context 'Exchange Online routing (RemoteSharedMailbox)' {
        It 'calls EXO permission functions and Set-AdUserSafe; returns Success=$true' {
            $snap = $script:ExecEXO
            Mock -ModuleName 'GroupMailboxService' Resolve-MailboxExecutionContext { $snap }
            Mock -ModuleName 'GroupMailboxService' Add-ExoMailboxPermissionSafe { }
            Mock -ModuleName 'GroupMailboxService' Add-ExoSendAsPermissionSafe { }
            Mock -ModuleName 'GroupMailboxService' Set-AdUserSafe { }
            Mock -ModuleName 'GroupMailboxService' Invoke-LegacyMailboxPermissionMutation { throw 'On-Prem should not be called for EXO mailbox' }

            $ctx = New-TestContext -ExoEnabled $true
            $row = New-CmRow
            $result = Set-GroupMailboxManager -Context $ctx -Data $row

            $result.Success   | Should -Be $true
            $result.Changed   | Should -Be $true
            $result.Authority | Should -Be 'ExchangeOnline'
            Should -Invoke Add-ExoMailboxPermissionSafe -ModuleName 'GroupMailboxService' -Times 1
            Should -Invoke Add-ExoSendAsPermissionSafe  -ModuleName 'GroupMailboxService' -Times 1
            # RemoteSharedMailbox still has an on-prem proxy → AD manager must also be updated
            Should -Invoke Set-AdUserSafe               -ModuleName 'GroupMailboxService' -Times 1
        }
    }

    Context 'Transient migration state (Retry)' {
        It 'returns RequiresRetry=$true and ErrorCode=MAILBOX_MIGRATION_TRANSIENT without calling any gateway' {
            $snap = $script:ExecRetry
            Mock -ModuleName 'GroupMailboxService' Resolve-MailboxExecutionContext { $snap }
            Mock -ModuleName 'GroupMailboxService' Invoke-LegacyMailboxPermissionMutation { throw 'Should not be called on Retry' }
            Mock -ModuleName 'GroupMailboxService' Add-ExoMailboxPermissionSafe { throw 'Should not be called on Retry' }

            $ctx = New-TestContext -ExoEnabled $true
            $row = New-CmRow
            $result = Set-GroupMailboxManager -Context $ctx -Data $row

            $result.Success       | Should -Be $false
            $result.RequiresRetry | Should -Be $true
            $result.ErrorCode     | Should -Be 'MAILBOX_MIGRATION_TRANSIENT'
            $result.Authority     | Should -Be 'ExchangeOnline'
        }
    }

    Context 'EXO required but disabled (Fail)' {
        It 'returns Success=$false and ErrorCode=EXO_REQUIRED_BUT_DISABLED' {
            $snap = $script:ExecFailExoDisabled
            Mock -ModuleName 'GroupMailboxService' Resolve-MailboxExecutionContext { $snap }
            Mock -ModuleName 'GroupMailboxService' Invoke-LegacyMailboxPermissionMutation { throw 'Should not be called on Fail' }
            Mock -ModuleName 'GroupMailboxService' Add-ExoMailboxPermissionSafe { throw 'Should not be called on Fail' }

            $ctx = New-TestContext -ExoEnabled $false
            $row = New-CmRow
            $result = Set-GroupMailboxManager -Context $ctx -Data $row

            $result.Success       | Should -Be $false
            $result.RequiresRetry | Should -Be $false
            $result.ErrorCode     | Should -Be 'EXO_REQUIRED_BUT_DISABLED'
            $result.Authority     | Should -Be 'ExchangeOnline'
        }
    }

    Context 'Mailbox not found (Fail, Unknown authority)' {
        It 'returns Success=$false and ErrorCode=MAILBOX_NOT_FOUND' {
            $snap = $script:ExecFailNotFound
            Mock -ModuleName 'GroupMailboxService' Resolve-MailboxExecutionContext { $snap }
            Mock -ModuleName 'GroupMailboxService' Invoke-LegacyMailboxPermissionMutation { throw 'Should not be called when not found' }
            Mock -ModuleName 'GroupMailboxService' Add-ExoMailboxPermissionSafe { throw 'Should not be called when not found' }

            $ctx = New-TestContext
            $row = New-CmRow
            $result = Set-GroupMailboxManager -Context $ctx -Data $row

            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'MAILBOX_NOT_FOUND'
        }
    }

    Context 'Gateway exception (On-Prem)' {
        It 'catches exception and returns Success=$false with ErrorCode=GROUP_MAILBOX_MANAGER_CHANGE_FAILED' {
            $snap = $script:ExecOnPrem
            Mock -ModuleName 'GroupMailboxService' Resolve-MailboxExecutionContext { $snap }
            Mock -ModuleName 'GroupMailboxService' Invoke-LegacyMailboxPermissionMutation { throw 'Simulated gateway error' }
            Mock -ModuleName 'GroupMailboxService' Set-AdUserSafe { }

            $ctx = New-TestContext
            $row = New-CmRow
            $result = Set-GroupMailboxManager -Context $ctx -Data $row

            $result.Success   | Should -Be $false
            $result.ErrorCode | Should -Be 'GROUP_MAILBOX_MANAGER_CHANGE_FAILED'
        }
    }

    Context 'WhatIf mode — no EXO connection required' {
        It 'returns Simulated=$true without importing or calling any EXO cmdlets' {
            # Even when EXO is enabled, WhatIf must not trigger any EXO connection
            Mock -ModuleName 'GroupMailboxService' Resolve-MailboxExecutionContext { throw 'Should not be called in WhatIf' }
            Mock -ModuleName 'GroupMailboxService' Add-ExoMailboxPermissionSafe { throw 'Should not be called in WhatIf' }

            $ctx = New-TestContext -ExoEnabled $true -WhatIfMode $true
            $row = New-CmRow
            $result = Set-GroupMailboxManager -Context $ctx -Data $row

            $result.Success   | Should -Be $true
            $result.Simulated | Should -Be $true
        }
    }

    Context 'WhatIf mode — no On-Prem Exchange cmdlets required' {
        It 'returns Simulated=$true without calling any On-Prem cmdlets' {
            Mock -ModuleName 'GroupMailboxService' Invoke-LegacyMailboxPermissionMutation { throw 'Should not be called in WhatIf' }
            Mock -ModuleName 'GroupMailboxService' Set-AdUserSafe { throw 'Should not be called in WhatIf' }

            $ctx = New-TestContext -WhatIfMode $true
            $row = New-CmRow
            $result = Set-GroupMailboxManager -Context $ctx -Data $row

            $result.Success   | Should -Be $true
            $result.Simulated | Should -Be $true
        }
    }
}

# ---------------------------------------------------------------------------
# Invoke-ChangeManagerGroupMailbox handler — RequiresRetry and routing
# ---------------------------------------------------------------------------
Describe 'Invoke-ChangeManagerGroupMailbox handler' {

    Context 'RequiresRetry propagation' {
        It 'returns Retry status when service returns RequiresRetry=$true' {
            $retrySvc = {
                param($Context, $Data)
                [pscustomobject]@{
                    Success           = $false
                    RequiresRetry     = $true
                    RetryAfterMinutes = 15
                    Message           = 'Migration transient state.'
                    AdObjectName      = $Data.AdObjectName
                }
            }
            $ctx = New-TestContext -ChangeManager $retrySvc
            $ctx | Add-Member -NotePropertyName Payload -NotePropertyValue @(New-CmRow) -Force

            $result = Invoke-ChangeManagerGroupMailbox -Context $ctx
            $result.Status | Should -Be 'Retry'
        }
    }

    Context 'Success' {
        It 'returns Succeeded status when service returns Success=$true' {
            $okSvc = {
                param($Context, $Data)
                [pscustomobject]@{ Success = $true; RequiresRetry = $false; Message = 'Done.' }
            }
            $ctx = New-TestContext -ChangeManager $okSvc
            $ctx | Add-Member -NotePropertyName Payload -NotePropertyValue @(New-CmRow) -Force

            $result = Invoke-ChangeManagerGroupMailbox -Context $ctx
            $result.Status | Should -Be 'Succeeded'
        }
    }

    Context 'Service failure (non-retry)' {
        It 'returns Failed status when service returns Success=$false without RequiresRetry' {
            $failSvc = {
                param($Context, $Data)
                [pscustomobject]@{
                    Success       = $false
                    RequiresRetry = $false
                    Message       = 'Mailbox not found.'
                    ErrorCode     = 'MAILBOX_NOT_FOUND'
                }
            }
            $ctx = New-TestContext -ChangeManager $failSvc
            $ctx | Add-Member -NotePropertyName Payload -NotePropertyValue @(New-CmRow) -Force

            $result = Invoke-ChangeManagerGroupMailbox -Context $ctx
            $result.Status | Should -Be 'Failed'
        }
    }

    Context 'Validation failure' {
        It 'returns Failed with USECASE_ERROR when required fields are missing' {
            $ctx = New-TestContext
            $ctx | Add-Member -NotePropertyName Payload -NotePropertyValue @(
                [pscustomobject]@{ ActionType = 'ChangeManager' }
            ) -Force

            $result = Invoke-ChangeManagerGroupMailbox -Context $ctx
            $result.Status    | Should -Be 'Failed'
            $result.ErrorCode | Should -Be 'USECASE_ERROR'
        }
    }

    Context 'Per-row partial failure' {
        It 'processes all rows and returns Failed when at least one row fails' {
            $script:cmCallCount = 0
            $mixedSvc = {
                param($Context, $Data)
                $script:cmCallCount++
                if ($script:cmCallCount -eq 1) {
                    [pscustomobject]@{ Success = $true;  RequiresRetry = $false; Message = 'OK';     AdObjectName = $Data.AdObjectName }
                }
                else {
                    [pscustomobject]@{ Success = $false; RequiresRetry = $false; Message = 'Failed'; AdObjectName = $Data.AdObjectName; ErrorCode = 'MAILBOX_NOT_FOUND' }
                }
            }
            $ctx = New-TestContext -ChangeManager $mixedSvc
            $ctx | Add-Member -NotePropertyName Payload -NotePropertyValue @(
                (New-CmRow -AdObjectName 'gmb-1'),
                (New-CmRow -AdObjectName 'gmb-2')
            ) -Force

            $result = Invoke-ChangeManagerGroupMailbox -Context $ctx
            $result.Status | Should -Be 'Failed'
        }
    }

    Context 'RequiresRetry stops further row processing' {
        It 'returns Retry after first row signals RequiresRetry without processing the second row' {
            $script:cmCallCount2 = 0
            $retryFirstSvc = {
                param($Context, $Data)
                $script:cmCallCount2++
                [pscustomobject]@{ Success = $false; RequiresRetry = $true; RetryAfterMinutes = 15; Message = 'Transient'; AdObjectName = $Data.AdObjectName }
            }
            $ctx = New-TestContext -ChangeManager $retryFirstSvc
            $ctx | Add-Member -NotePropertyName Payload -NotePropertyValue @(
                (New-CmRow -AdObjectName 'gmb-a'),
                (New-CmRow -AdObjectName 'gmb-b')
            ) -Force

            $result = Invoke-ChangeManagerGroupMailbox -Context $ctx

            $result.Status         | Should -Be 'Retry'
            $script:cmCallCount2   | Should -Be 1  # second row must NOT be processed
        }
    }
}

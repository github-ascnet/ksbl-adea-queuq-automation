BeforeAll {
    $root = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

    Import-Module -Name (Join-Path $root 'core\JobResult.psm1') -Force
    Import-Module -Name (Join-Path $root 'core\Validation.psm1') -Force
    Import-Module -Name (Join-Path $root 'core\Logging.psm1') -Force
    Import-Module -Name (Join-Path $root 'infrastructure\ActiveDirectoryGateway.psm1') -Force
    Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnPremGateway.psm1') -Force
    Import-Module -Name (Join-Path $root 'shared\GroupMailboxService.psm1') -Force
    Import-Module -Name (Join-Path $root 'shared\DistributionGroupService.psm1') -Force
    Import-Module -Name (Join-Path $root 'usecases\GroupMailbox\AddGroupMailboxFmaMembers.psm1') -Force
    Import-Module -Name (Join-Path $root 'usecases\GroupMailbox\ChangeManagerGroupMailbox.psm1') -Force
    Import-Module -Name (Join-Path $root 'usecases\DistributionGroup\AddDistributionListResponsibles.psm1') -Force
    Import-Module -Name (Join-Path $root 'usecases\DistributionGroup\ChangeManagerDistribList.psm1') -Force

    function New-TestLogger {
        [pscustomobject]@{
            RunId           = 'test'
            LogFile         = (Join-Path $TestDrive 'test.log')
            ConsoleEnabled  = $false
            FileEnabled     = $false
            EventLogEnabled = $false
            EventLogName    = 'Application'
            EventSource     = 'MailboxAutomation.Tests'
            VerboseLogging  = $false
        }
    }

    function New-GroupMailboxFmaRow {
        [pscustomobject]@{
            ActionType               = 'AddGroupMailboxFmaMembers'
            AdObjectName             = 'gmb-test'
            FullAccessMembers        = 'us001[ADD]!us002[DEL]'
            EnableSendAs             = 'True'
            CurrentUserName          = 'Requester'
            CurrentUserDomainName    = 'DOMAIN'
            CurrentUserEMailAddress  = 'requester@example.org'
        }
    }

    function New-GroupMailboxChangeManagerRow {
        [pscustomobject]@{
            ActionType               = 'ChangeManagerGroupMailbox'
            AdObjectName             = 'gmb-test'
            ManagerAdObjectName      = 'us-manager'
            CurrentUserName          = 'Requester'
            CurrentUserDomainName    = 'DOMAIN'
            CurrentUserEMailAddress  = 'requester@example.org'
        }
    }

    function New-DistributionResponsiblesRow {
        [pscustomobject]@{
            ActionType               = 'AddDistributionListResponsibles'
            AdObjectName             = 'dl-test'
            ManagedByMembers         = 'us001[ADD]!us002[DEL]'
            CurrentUserName          = 'Requester'
            CurrentUserDomainName    = 'DOMAIN'
            CurrentUserEMailAddress  = 'requester@example.org'
        }
    }

    function New-DistributionChangeManagerRow {
        [pscustomobject]@{
            ActionType               = 'ChangeManagerDistribList'
            AdObjectName             = 'dl-test'
            ManagerAdObjectName      = 'us-manager'
            CurrentUserName          = 'Requester'
            CurrentUserDomainName    = 'DOMAIN'
            CurrentUserEMailAddress  = 'requester@example.org'
        }
    }

}

Describe 'Migrated GroupMailbox handlers' {
    It 'GroupMailbox.AddFmaMembers returns Succeeded when service succeeds' {
        $context = [pscustomobject]@{
            Payload    = @(New-GroupMailboxFmaRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = @{ GroupMailbox = [pscustomobject]@{ AddFmaMembers = { param($Context, $Data) [pscustomobject]@{ Success = $true; Changed = $true; Message = 'ok'; ErrorCode = $null } } } }
        }

        $result = Invoke-AddGroupMailboxFmaMembers -Context $context
        $result.Status | Should -Be 'Succeeded'
        $result.Output.Count | Should -Be 1
    }

    It 'GroupMailbox.AddFmaMembers returns Failed when service fails' {
        $context = [pscustomobject]@{
            Payload    = @(New-GroupMailboxFmaRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = @{ GroupMailbox = [pscustomobject]@{ AddFmaMembers = { param($Context, $Data) [pscustomobject]@{ Success = $false; Changed = $false; Message = 'missing'; ErrorCode = 'GROUP_MAILBOX_NOT_FOUND' } } } }
        }

        $result = Invoke-AddGroupMailboxFmaMembers -Context $context
        $result.Status | Should -Be 'Failed'
        $result.ErrorCode | Should -Be 'GROUP_MAILBOX_FMA_MEMBERS_FAILED'
    }

    It 'GroupMailbox.ChangeManager returns Succeeded when service succeeds' {
        $context = [pscustomobject]@{
            Payload    = @(New-GroupMailboxChangeManagerRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = @{ GroupMailbox = [pscustomobject]@{ ChangeManager = { param($Context, $Data) [pscustomobject]@{ Success = $true; Changed = $true; Message = 'ok'; ErrorCode = $null } } } }
        }

        $result = Invoke-ChangeManagerGroupMailbox -Context $context
        $result.Status | Should -Be 'Succeeded'
    }
}

Describe 'Migrated DistributionGroup handlers' {
    It 'DistributionGroup.AddResponsibles returns Succeeded when service succeeds' {
        $context = [pscustomobject]@{
            Payload    = @(New-DistributionResponsiblesRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = @{ DistributionGroup = [pscustomobject]@{ AddResponsibles = { param($Context, $Data) [pscustomobject]@{ Success = $true; Changed = $true; Message = 'ok'; ErrorCode = $null } } } }
        }

        $result = Invoke-AddDistributionListResponsibles -Context $context
        $result.Status | Should -Be 'Succeeded'
    }

    It 'DistributionGroup.ChangeManager returns Succeeded when service succeeds' {
        $context = [pscustomobject]@{
            Payload    = @(New-DistributionChangeManagerRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = @{ DistributionGroup = [pscustomobject]@{ ChangeManager = { param($Context, $Data) [pscustomobject]@{ Success = $true; Changed = $true; Message = 'ok'; ErrorCode = $null } } } }
        }

        $result = Invoke-ChangeManagerDistribList -Context $context
        $result.Status | Should -Be 'Succeeded'
    }
}

Describe 'Migrated GroupMailbox and DistributionGroup services' {
    It 'Add-GroupMailboxFmaMembers returns simulated operations in WhatIfMode' {
        $context = [pscustomobject]@{ Logger = New-TestLogger; WhatIfMode = $true }
        $result = Add-GroupMailboxFmaMembers -Context $context -Data (New-GroupMailboxFmaRow)

        $result.Success | Should -Be $true
        $result.Simulated | Should -Be $true
        $result.Operations.Count | Should -Be 2
        $result.Operations[0].Trustee | Should -Be 'us001'
        $result.Operations[0].Action | Should -Be 'ADD'
    }

    It 'Set-GroupMailboxManager returns simulated result in WhatIfMode' {
        $context = [pscustomobject]@{ Logger = New-TestLogger; WhatIfMode = $true }
        $result = Set-GroupMailboxManager -Context $context -Data (New-GroupMailboxChangeManagerRow)

        $result.Success | Should -Be $true
        $result.Simulated | Should -Be $true
        $result.Manager | Should -Be 'us-manager'
    }

    It 'Add-DistributionListResponsibles returns simulated operations in WhatIfMode' {
        $context = [pscustomobject]@{ Logger = New-TestLogger; WhatIfMode = $true }
        $result = Add-DistributionListResponsibles -Context $context -Data (New-DistributionResponsiblesRow)

        $result.Success | Should -Be $true
        $result.Simulated | Should -Be $true
        $result.Operations.Count | Should -Be 2
        $result.Operations[0].Responsible | Should -Be 'us001'
    }

    It 'Set-DistributionGroupManager returns simulated result in WhatIfMode' {
        $context = [pscustomobject]@{ Logger = New-TestLogger; WhatIfMode = $true }
        $result = Set-DistributionGroupManager -Context $context -Data (New-DistributionChangeManagerRow)

        $result.Success | Should -Be $true
        $result.Simulated | Should -Be $true
        $result.Manager | Should -Be 'us-manager'
    }
}

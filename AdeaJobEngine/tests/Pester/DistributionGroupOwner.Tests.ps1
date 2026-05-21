Set-StrictMode -Version Latest

$root = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

Import-Module -Name (Join-Path $root 'core\JobResult.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'core\Validation.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'core\Logging.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnPremGateway.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'shared\DistributionGroupService.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'usecases\DistributionGroup\ChangeDistributionGroupOwner.psm1') -Force -DisableNameChecking

BeforeAll {
    function New-TestLogger {
        [pscustomobject]@{
            RunId           = 'test-dg-owner'
            LogFile         = (Join-Path $TestDrive 'dg-owner.log')
            ConsoleEnabled  = $false
            FileEnabled     = $false
            EventLogEnabled = $false
            EventLogName    = 'Application'
            EventSource     = 'AdeaJobEngine.Tests'
            VerboseLogging  = $false
        }
    }

    function New-OwnerRow {
        param(
            [string]$GroupIdentity = 'dl-test',
            [string]$OwnerIdentity = 'user1[ADD]'
        )
        [pscustomobject]@{
            GroupIdentity = $GroupIdentity
            OwnerIdentity = $OwnerIdentity
        }
    }
}

Describe 'DistributionGroup.ChangeOwner handler' {
    It 'fails when required fields are missing' {
        $context = [pscustomobject]@{
            Payload = @([pscustomobject]@{ GroupIdentity = 'dl-test' })
            Logger  = New-TestLogger
        }

        $result = Invoke-ChangeDistributionGroupOwner -Context $context
        $result.Status | Should -Be 'Failed'
        $result.ErrorCode | Should -Be 'USECASE_ERROR'
    }

    It 'returns Succeeded when service succeeds' {
        Mock -ModuleName 'ChangeDistributionGroupOwner' -CommandName Update-DistributionGroupManagedByMembers { [pscustomobject]@{ Success = $true; Changed = $true; Message = 'ok'; ErrorCode = $null } }
        $context = [pscustomobject]@{ Payload = @(New-OwnerRow); Logger = New-TestLogger }

        $result = Invoke-ChangeDistributionGroupOwner -Context $context
        $result.Status | Should -Be 'Succeeded'
    }

    It 'does not call Set-DistributionGroup directly in handler' {
        $content = Get-Content -Path (Join-Path $root 'usecases\DistributionGroup\ChangeDistributionGroupOwner.psm1') -Raw
        $content | Should -Not -Match '(?i)Set-DistributionGroup'
    }

    It 'does not reference ExchangeOnline in handler' {
        $content = Get-Content -Path (Join-Path $root 'usecases\DistributionGroup\ChangeDistributionGroupOwner.psm1') -Raw
        $content | Should -Not -Match '(?i)ExchangeOnline|Connect-ExchangeOnline|EXO'
    }
}

Describe 'DistributionGroup ManagedBy service' {
    It 'parses [ADD] and calls gateway with ManagedBy Add' {
        Mock -ModuleName 'DistributionGroupService' Set-OnPremDistributionGroupSafe {}
        $context = [pscustomobject]@{ Logger = New-TestLogger; WhatIfMode = $false }
        $data = New-OwnerRow -OwnerIdentity 'user1[ADD]'

        $result = Update-DistributionGroupManagedByMembers -Context $context -Data $data
        $result.Success | Should -Be $true
        Should -Invoke Set-OnPremDistributionGroupSafe -ModuleName 'DistributionGroupService' -Times 1 -ParameterFilter {
            $Parameters.Identity -eq 'dl-test' -and $Parameters.ManagedBy.Add -eq 'user1' -and $Parameters.BypassSecurityGroupManagerCheck -eq $true
        }
    }

    It 'parses [DEL] and calls gateway with ManagedBy Remove' {
        Mock -ModuleName 'DistributionGroupService' Set-OnPremDistributionGroupSafe {}
        $context = [pscustomobject]@{ Logger = New-TestLogger; WhatIfMode = $false }
        $data = New-OwnerRow -OwnerIdentity 'user2[DEL]'

        $result = Update-DistributionGroupManagedByMembers -Context $context -Data $data
        $result.Success | Should -Be $true
        Should -Invoke Set-OnPremDistributionGroupSafe -ModuleName 'DistributionGroupService' -Times 1 -ParameterFilter {
            $Parameters.Identity -eq 'dl-test' -and $Parameters.ManagedBy.Remove -eq 'user2' -and $Parameters.BypassSecurityGroupManagerCheck -eq $true
        }
    }

    It 'rejects tokens without [ADD]/[DEL]' {
        $context = [pscustomobject]@{ Logger = New-TestLogger; WhatIfMode = $false }
        $data = New-OwnerRow -OwnerIdentity 'user3'

        $result = Update-DistributionGroupManagedByMembers -Context $context -Data $data
        $result.Success | Should -Be $false
        $result.ErrorCode | Should -Be 'DISTRIBUTION_GROUP_OWNER_CHANGE_FAILED'
    }

    It 'does not reference ExchangeOnline in service' {
        $content = Get-Content -Path (Join-Path $root 'shared\DistributionGroupService.psm1') -Raw
        $content | Should -Not -Match '(?i)ExchangeOnline|Connect-ExchangeOnline|EXO'
    }
}

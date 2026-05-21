#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path

    Import-Module -Name (Join-Path $script:root 'shared\Naming.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $script:root 'infrastructure\ActiveDirectoryGateway.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $script:root 'shared\AccountNameGenerator.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $script:root 'infrastructure\ExchangeOnPremGateway.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $script:root 'infrastructure\ExchangeOnlineGateway.psm1') -Force -DisableNameChecking

    if (-not (Get-Command -Name Invoke-Sqlcmd -ErrorAction SilentlyContinue)) {
        function Invoke-Sqlcmd { }
    }
}

Describe 'AccountName generation via On-Prem AD' {
    BeforeEach {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @() }
        }
    }

    It 'Prefix gmb without existing accounts yields gmb0001 (Test 1)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @() }
            Get-NextAvailableSamAccountName -Prefix gmb | Should -Be 'gmb0001'
        }
    }

    It 'Prefix us without existing accounts yields us10000 (Test 2)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @() }
            Get-NextAvailableSamAccountName -Prefix us | Should -Be 'us10000'
        }
    }

    It 'Prefix ex without existing accounts yields ex00100 (Test 3)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @() }
            Get-NextAvailableSamAccountName -Prefix ex | Should -Be 'ex00100'
        }
    }

    It 'gmb with gmb0001 and gmb0002 yields gmb0003 (Test 4)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @('gmb0001', 'gmb0002') }
            Get-NextAvailableSamAccountName -Prefix gmb | Should -Be 'gmb0003'
        }
    }

    It 'gmb with gap gmb0001, gmb0002, gmb0004 yields gmb0003 (Test 5)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @('gmb0001', 'gmb0002', 'gmb0004') }
            Get-NextAvailableSamAccountName -Prefix gmb | Should -Be 'gmb0003'
        }
    }

    It 'gmb UseHighestPlusOne yields gmb0005 (Test 6)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @('gmb0001', 'gmb0002', 'gmb0004') }
            Get-NextAvailableSamAccountName -Prefix gmb -UseHighestPlusOne | Should -Be 'gmb0005'
        }
    }

    It 'us with us10000 and us10001 yields us10002 (Test 7)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @('us10000', 'us10001') }
            Get-NextAvailableSamAccountName -Prefix us | Should -Be 'us10002'
        }
    }

    It 'ex with ex00100 and ex00101 yields ex00102 (Test 8)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @('ex00100', 'ex00101') }
            Get-NextAvailableSamAccountName -Prefix ex | Should -Be 'ex00102'
        }
    }

    It 'invalid formats are ignored (Test 9)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @('gmbABC', 'gmb0001_old', 'user00100', 'gmb0001') }
            Get-NextAvailableSamAccountName -Prefix gmb | Should -Be 'gmb0002'
        }
    }

    It 'out-of-range values are ignored (Test 10)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @('gmb0000', 'gmb10000') }
            Get-NextAvailableSamAccountName -Prefix gmb | Should -Be 'gmb0001'
        }
    }

    It 'exhausted range throws controlled error (Test 11)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @('gmb9999') }
            { Get-NextAvailableSamAccountName -Prefix gmb -UseHighestPlusOne } | Should -Throw
        }
    }

    It 'Prefix is case-insensitive (Test 12)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @() }
            Get-NextAvailableSamAccountName -Prefix GMB | Should -Be 'gmb0001'
        }
    }

    It 'Invalid prefix is rejected (Test 13)' {
        InModuleScope AccountNameGenerator {
            { Get-NextAvailableSamAccountName -Prefix abc } | Should -Throw
        }
    }

    It 'Get-NextAvailableAccountName gmbTest uses gmb logic (Test 14)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @() }
            Get-NextAvailableAccountName -BaseName 'gmbTest' | Should -Be 'gmb0001'
        }
    }

    It 'Get-NextAvailableAccountName usTest uses us logic (Test 15)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @() }
            Get-NextAvailableAccountName -BaseName 'usTest' | Should -Be 'us10000'
        }
    }

    It 'Get-NextAvailableAccountName exTest uses ex logic (Test 16)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @() }
            Get-NextAvailableAccountName -BaseName 'exTest' | Should -Be 'ex00100'
        }
    }

    It 'Get-NextAvailableAccountName with unknown prefix throws (Test 17)' {
        InModuleScope AccountNameGenerator {
            { Get-NextAvailableAccountName -BaseName 'admin' } | Should -Throw
        }
    }

    It 'AD search is mocked via gateway (Test 18)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @() }
            Get-NextAvailableSamAccountName -Prefix gmb | Should -Be 'gmb0001'
            Should -Invoke Get-AdSamAccountNamesByPrefix -Times 1
        }
    }

    It 'no real AD query is executed (Test 19)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @() }
            Mock -CommandName Search-AdUserByLdapFilterSafe -MockWith { throw 'should not be called' }

            Get-NextAvailableSamAccountName -Prefix gmb | Should -Be 'gmb0001'
            Should -Invoke Search-AdUserByLdapFilterSafe -Times 0
        }
    }

    It 'ExchangeOnPremGateway is not used (Test 20)' {
        InModuleScope AccountNameGenerator {
            Mock -ModuleName ExchangeOnPremGateway Get-ExchangeOnPremSession { throw 'should not be called' }
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @() }

            Get-NextAvailableSamAccountName -Prefix gmb | Should -Be 'gmb0001'
            Should -Invoke Get-ExchangeOnPremSession -ModuleName ExchangeOnPremGateway -Times 0
        }
    }

    It 'ExchangeOnlineGateway is not used (Test 21)' {
        InModuleScope AccountNameGenerator {
            Mock -ModuleName ExchangeOnlineGateway Ensure-ExchangeOnlineSession { throw 'should not be called' }
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @() }

            Get-NextAvailableSamAccountName -Prefix gmb | Should -Be 'gmb0001'
            Should -Invoke Ensure-ExchangeOnlineSession -ModuleName ExchangeOnlineGateway -Times 0
        }
    }

    It 'no EXO or Exchange cmdlets are used for name checks (Test 22)' {
        $content = Get-Content -Path (Join-Path $script:root 'shared\AccountNameGenerator.psm1') -Raw
        $content | Should -Not -Match '(?i)Get-Recipient|Get-EXORecipient|Get-Mailbox'
    }

    It 'SQL is not used as source of truth (Test 23)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Invoke-Sqlcmd { throw 'should not be called' }
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @() }

            Get-NextAvailableSamAccountName -Prefix gmb | Should -Be 'gmb0001'
            Should -Invoke Invoke-Sqlcmd -Times 0
        }
    }

    It 'result is always lower-case (Test 24)' {
        InModuleScope AccountNameGenerator {
            Mock -CommandName Get-AdSamAccountNamesByPrefix -MockWith { @() }
            Get-NextAvailableSamAccountName -Prefix GMB | Should -Be 'gmb0001'
        }
    }
}

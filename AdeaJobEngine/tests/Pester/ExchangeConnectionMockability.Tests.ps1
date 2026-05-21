#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
    Import-Module -Name (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeConnectionHealth.psm1') -Force
    Import-Module -Name (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnPremGateway.psm1') -Force
    Import-Module -Name (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnlineGateway.psm1') -Force
}

Describe 'Exchange connection mockability and diagnostics' {
    It 'OutputJson from diagnostic script is valid JSON (Test 13)' {
        $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
        $scriptPath = Join-Path -Path $root -ChildPath 'tools\Test-ExchangeConnections.ps1'

        $json = & $scriptPath -Environment hybrid -Target ExchangeOnline -OutputJson
        { $json | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw
    }

    It 'does not force a new OnPrem session without EnsureConnected (Test 14)' {
        InModuleScope ExchangeOnPremGateway {
            $config = @{ ExchangeOnPrem = @{ RemotePowerShell = @{ Enabled = $true; User = 'u'; ConnectionUri = 'http://x'; SecretPath = 'c:\x' } } }
            $script:ExchangeOnPremSessionState.Session = $null

            Mock Get-ExchangeOnPremSession { throw 'should not be called' }

            $result = Test-ExchangeOnPremConnectionHealth -Config $config
            $result.Status | Should -Be 'NotConnected'
            Should -Invoke Get-ExchangeOnPremSession -Times 0
        }
    }

    It 'uses wrapper functions for validation commands (Test 15)' {
        InModuleScope ExchangeOnPremGateway {
            $config = @{ ExchangeOnPrem = @{ RemotePowerShell = @{ Enabled = $true; User = 'u'; ConnectionUri = 'http://x'; SecretPath = 'c:\x' } } }
            $script:ExchangeOnPremSessionState.Session = [pscustomobject]@{ State = 'Opened' }

            Mock Invoke-ExchangeOnPremCommandInternal { 'ok' }

            $result = Test-ExchangeOnPremConnectionHealth -Config $config -ValidateCommand
            $result.Status | Should -Be 'Connected'
            Should -Invoke Invoke-ExchangeOnPremCommandInternal -Times 1
        }

        InModuleScope ExchangeOnlineGateway {
            $config = @{ ExchangeOnline = @{ Enabled = $true; AppId = 'a'; Organization = 'o'; CertificateThumbprint = 'AABB'; ConnectionValidationCommand = 'Get-EXORecipient'; ConnectionValidationResultSize = 1 } }

            Mock Get-ExchangeOnlineModuleInternal { $null }
            Mock Get-ExchangeOnlineModuleAvailableInternal { [pscustomobject]@{ Name = 'ExchangeOnlineManagement' } }
            Mock Get-ExchangeOnlineCertificateInternal {
                [pscustomobject]@{ Thumbprint = 'AABB'; HasPrivateKey = $true; NotAfter = (Get-Date).AddYears(1) }
            }
            Mock Get-ExchangeOnlineConnectionInformationInternal {
                [pscustomobject]@{ State = 'Connected'; ConnectionUri = 'https://outlook.office365.com' }
            }
            Mock Invoke-ExchangeOnlineValidationCommandInternal { 'ok' }

            $result = Test-ExchangeOnlineConnectionHealth -Config $config -ValidateCommand
            $result.Status | Should -Be 'Connected'
            Should -Invoke Invoke-ExchangeOnlineValidationCommandInternal -Times 1
        }
    }
}

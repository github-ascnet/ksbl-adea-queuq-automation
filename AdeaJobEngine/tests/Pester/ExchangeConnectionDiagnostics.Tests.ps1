#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
    Import-Module -Name (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeConnectionHealth.psm1') -Force
    Import-Module -Name (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnPremGateway.psm1') -Force
    Import-Module -Name (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnlineGateway.psm1') -Force
}

Describe 'Exchange connection health diagnostics' {
    It 'OnPrem health result has Target and ConnectionType (Test 2)' {
        InModuleScope ExchangeOnPremGateway {
            $config = @{ ExchangeOnPrem = @{ RemotePowerShell = @{ Enabled = $false } } }
            $result = Test-ExchangeOnPremConnectionHealth -Config $config

            $result.Target | Should -Be 'ExchangeOnPrem'
            $result.ConnectionType | Should -Be 'RemotePowerShellInvokeCommand'
        }
    }

    It 'EXO health result has Target and ConnectionType (Test 3)' {
        InModuleScope ExchangeOnlineGateway {
            $config = @{ ExchangeOnline = @{ Enabled = $false } }
            $result = Test-ExchangeOnlineConnectionHealth -Config $config

            $result.Target | Should -Be 'ExchangeOnline'
            $result.ConnectionType | Should -Be 'ExchangeOnlineManagementAppOnly'
        }
    }

    It 'disabled config yields Status Disabled (Test 4)' {
        InModuleScope ExchangeOnlineGateway {
            $config = @{ ExchangeOnline = @{ Enabled = $false } }
            $result = Test-ExchangeOnlineConnectionHealth -Config $config

            $result.Status | Should -Be 'Disabled'
        }
    }

    It 'missing config yields Status NotConfigured (Test 5)' {
        InModuleScope ExchangeOnlineGateway {
            $result = Test-ExchangeOnlineConnectionHealth
            $result.Status | Should -Be 'NotConfigured'
        }
    }

    It 'missing EXO module yields Status MissingModule (Test 6)' {
        InModuleScope ExchangeOnlineGateway {
            $config = @{ ExchangeOnline = @{ Enabled = $true; AppId = 'a'; Organization = 'o'; CertificateThumbprint = 'A' } }
            Mock Get-ExchangeOnlineModuleInternal { $null }
            Mock Get-ExchangeOnlineModuleAvailableInternal { $null }

            $result = Test-ExchangeOnlineConnectionHealth -Config $config
            $result.Status | Should -Be 'MissingModule'
        }
    }

    It 'missing certificate yields Status CertificateMissing (Test 7)' {
        InModuleScope ExchangeOnlineGateway {
            $config = @{ ExchangeOnline = @{ Enabled = $true; AppId = 'a'; Organization = 'o'; CertificateThumbprint = 'AABB' } }
            Mock Get-ExchangeOnlineModuleInternal { $null }
            Mock Get-ExchangeOnlineModuleAvailableInternal { [pscustomobject]@{ Name = 'ExchangeOnlineManagement' } }
            Mock Get-ExchangeOnlineCertificateInternal { $null }

            $result = Test-ExchangeOnlineConnectionHealth -Config $config
            $result.Status | Should -Be 'CertificateMissing'
        }
    }

    It 'certificate without private key yields Status CertificatePrivateKeyMissing (Test 8)' {
        InModuleScope ExchangeOnlineGateway {
            $config = @{ ExchangeOnline = @{ Enabled = $true; AppId = 'a'; Organization = 'o'; CertificateThumbprint = 'AABB' } }
            Mock Get-ExchangeOnlineModuleInternal { $null }
            Mock Get-ExchangeOnlineModuleAvailableInternal { [pscustomobject]@{ Name = 'ExchangeOnlineManagement' } }
            Mock Get-ExchangeOnlineCertificateInternal {
                [pscustomobject]@{ Thumbprint = 'AABB'; HasPrivateKey = $false; NotAfter = (Get-Date).AddYears(1) }
            }

            $result = Test-ExchangeOnlineConnectionHealth -Config $config
            $result.Status | Should -Be 'CertificatePrivateKeyMissing'
        }
    }

    It 'expired certificate yields Status CertificateExpired (Test 9)' {
        InModuleScope ExchangeOnlineGateway {
            $config = @{ ExchangeOnline = @{ Enabled = $true; AppId = 'a'; Organization = 'o'; CertificateThumbprint = 'AABB' } }
            Mock Get-ExchangeOnlineModuleInternal { $null }
            Mock Get-ExchangeOnlineModuleAvailableInternal { [pscustomobject]@{ Name = 'ExchangeOnlineManagement' } }
            Mock Get-ExchangeOnlineCertificateInternal {
                [pscustomobject]@{ Thumbprint = 'AABB'; HasPrivateKey = $true; NotAfter = (Get-Date).AddYears(-1) }
            }
            Mock Get-EXODateInternal { Get-Date }

            $result = Test-ExchangeOnlineConnectionHealth -Config $config
            $result.Status | Should -Be 'CertificateExpired'
        }
    }

    It 'broken OnPrem session yields Status Unusable or NotConnected (Test 10)' {
        InModuleScope ExchangeOnPremGateway {
            $config = @{ ExchangeOnPrem = @{ RemotePowerShell = @{ Enabled = $true; User = 'u'; ConnectionUri = 'http://x'; SecretPath = 'c:\x' } } }
            $script:ExchangeOnPremSessionState.Session = [pscustomobject]@{ State = 'Broken' }

            $result = Test-ExchangeOnPremConnectionHealth -Config $config
            $result.Status | Should -BeIn @('Unusable', 'NotConnected')
        }
    }

    It 'successful OnPrem session yields Status Connected (Test 11)' {
        InModuleScope ExchangeOnPremGateway {
            $config = @{ ExchangeOnPrem = @{ RemotePowerShell = @{ Enabled = $true; User = 'u'; ConnectionUri = 'http://x'; SecretPath = 'c:\x' } } }
            $script:ExchangeOnPremSessionState.Session = [pscustomobject]@{ State = 'Opened' }

            $result = Test-ExchangeOnPremConnectionHealth -Config $config
            $result.Status | Should -Be 'Connected'
        }
    }

    It 'successful EXO connection information yields Status Connected (Test 12)' {
        InModuleScope ExchangeOnlineGateway {
            $config = @{ ExchangeOnline = @{ Enabled = $true; AppId = 'a'; Organization = 'o'; CertificateThumbprint = 'AABB' } }
            Mock Get-ExchangeOnlineModuleInternal { $null }
            Mock Get-ExchangeOnlineModuleAvailableInternal { [pscustomobject]@{ Name = 'ExchangeOnlineManagement' } }
            Mock Get-ExchangeOnlineCertificateInternal {
                [pscustomobject]@{ Thumbprint = 'AABB'; HasPrivateKey = $true; NotAfter = (Get-Date).AddYears(1) }
            }
            Mock Get-ExchangeOnlineConnectionInformationInternal {
                [pscustomobject]@{ State = 'Connected'; ConnectionUri = 'https://outlook.office365.com' }
            }

            $result = Test-ExchangeOnlineConnectionHealth -Config $config
            $result.Status | Should -Be 'Connected'
        }
    }
}

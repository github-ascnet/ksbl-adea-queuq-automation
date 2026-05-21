#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
    Import-Module -Name (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnlineGateway.psm1') -Force -DisableNameChecking

    $script:configDir = Join-Path -Path $root -ChildPath 'config'
    $script:appRaw = Get-Content -Path (Join-Path $script:configDir 'appsettings.json')       -Raw -Encoding UTF8
    $script:hybridRaw = Get-Content -Path (Join-Path $script:configDir 'environments.hybrid.json') -Raw -Encoding UTF8
    $script:appSettings = $script:appRaw    | ConvertFrom-Json
    $script:hybridConfig = $script:hybridRaw | ConvertFrom-Json

    # Hilfsfunktion: valide minimale EXO-Konfiguration als Hashtable
    function New-ValidEXOConfig {
        param(
            [string]$AppId = 'test-app-id',
            [string]$Organization = 'test.onmicrosoft.com',
            [string]$Thumbprint = 'AABBCCDD',
            [bool]  $Enabled = $true,
            [bool]  $ReuseSession = $true,
            [bool]  $ReconnectOnFail = $true,
            [bool]  $ValidateWithCmd = $false
        )
        return @{
            ExchangeOnline = @{
                Enabled                        = $Enabled
                AppId                          = $AppId
                Organization                   = $Organization
                CertificateThumbprint          = $Thumbprint
                ReuseSession                   = $ReuseSession
                ReconnectOnFailure             = $ReconnectOnFail
                MaxReconnectAttempts           = 1
                ValidateConnectionWithCommand  = $ValidateWithCmd
                ConnectionValidationCommand    = 'Get-EXORecipient'
                ConnectionValidationResultSize = 1
            }
        }
    }
}

Describe 'ExchangeOnlineSession – Konfiguration lesen und validieren' {

    # ─── Test 1: Korrekte Konfiguration wird gelesen ───────────────────────
    It 'liest EXO-Konfiguration korrekt und gibt alle Felder zurück (Test 1)' {
        InModuleScope ExchangeOnlineGateway {
            $config = @{
                ExchangeOnline = @{
                    Enabled                        = $true
                    AppId                          = 'my-app-id'
                    Organization                   = 'contoso.onmicrosoft.com'
                    TenantDomain                   = 'contoso.onmicrosoft.com'
                    CertificateThumbprint          = 'ABCDEF1234'
                    ShowBanner                     = $false
                    ReuseSession                   = $true
                    ReconnectOnFailure             = $true
                    MaxReconnectAttempts           = 1
                    ValidateConnectionWithCommand  = $true
                    ConnectionValidationCommand    = 'Get-EXORecipient'
                    ConnectionValidationResultSize = 1
                }
            }

            $result = Get-ExchangeOnlineRemotePowerShellConfig -Config $config

            $result.AppId                 | Should -Be 'my-app-id'
            $result.Organization          | Should -Be 'contoso.onmicrosoft.com'
            $result.CertificateThumbprint | Should -Be 'ABCDEF1234'
            $result.ReuseSession          | Should -Be $true
            $result.ReconnectOnFailure    | Should -Be $true
            $result.MaxReconnectAttempts  | Should -Be 1
            $result.ValidateConnectionWithCommand  | Should -Be $true
            $result.ConnectionValidationCommand    | Should -Be 'Get-EXORecipient'
            $result.ConnectionValidationResultSize | Should -Be 1
        }
    }

    # ─── Test 2: Enabled=false führt zu kontrolliertem Abbruch ─────────────
    It 'wirft kontrollierten Fehler wenn ExchangeOnline.Enabled=false (Test 2)' {
        InModuleScope ExchangeOnlineGateway {
            $config = @{
                ExchangeOnline = @{
                    Enabled               = $false
                    AppId                 = 'x'
                    Organization          = 'x.onmicrosoft.com'
                    CertificateThumbprint = 'AABB'
                }
            }

            { Get-ExchangeOnlineRemotePowerShellConfig -Config $config } | Should -Throw -ExpectedMessage '*Enabled=false*'
        }
    }

    # ─── Test 3: Fehlende AppId führt zu kontrolliertem Abbruch ────────────
    It 'wirft kontrollierten Fehler wenn AppId fehlt (Test 3)' {
        InModuleScope ExchangeOnlineGateway {
            $config = @{
                ExchangeOnline = @{
                    Enabled               = $true
                    AppId                 = ''
                    Organization          = 'x.onmicrosoft.com'
                    CertificateThumbprint = 'AABB'
                }
            }

            { Get-ExchangeOnlineRemotePowerShellConfig -Config $config } | Should -Throw -ExpectedMessage "*'AppId'*"
        }
    }

    # ─── Test 4: Fehlende Organization UND TenantDomain → Abbruch ──────────
    It 'wirft kontrollierten Fehler wenn weder Organization noch TenantDomain gesetzt ist (Test 4)' {
        InModuleScope ExchangeOnlineGateway {
            $config = @{
                ExchangeOnline = @{
                    Enabled               = $true
                    AppId                 = 'test-id'
                    Organization          = ''
                    TenantDomain          = ''
                    CertificateThumbprint = 'AABB'
                }
            }

            { Get-ExchangeOnlineRemotePowerShellConfig -Config $config } | Should -Throw -ExpectedMessage "*Organization*"
        }
    }

    # ─── Test 5: Fehlendes CertificateThumbprint → Abbruch ─────────────────
    It 'wirft kontrollierten Fehler wenn CertificateThumbprint fehlt (Test 5)' {
        InModuleScope ExchangeOnlineGateway {
            $config = @{
                ExchangeOnline = @{
                    Enabled               = $true
                    AppId                 = 'test-id'
                    Organization          = 'x.onmicrosoft.com'
                    CertificateThumbprint = ''
                }
            }

            { Get-ExchangeOnlineRemotePowerShellConfig -Config $config } | Should -Throw -ExpectedMessage "*'CertificateThumbprint'*"
        }
    }

    # ─── Test 6: Fehlende Zertifikat im Speicher → klare Diagnose ──────────
    It 'liefert klare Diagnose wenn Zertifikat nicht im Speicher gefunden wird (Test 6)' {
        InModuleScope ExchangeOnlineGateway {
            Mock Get-ExchangeOnlineCertificateInternal { $null }

            { Test-ExchangeOnlineCertificate -Thumbprint 'NOTFOUND' } |
            Should -Throw -ExpectedMessage '*nicht gefunden*'
        }
    }

    # ─── Test 7: Zertifikat ohne Private Key → klare Diagnose ──────────────
    It 'liefert klare Diagnose wenn Zertifikat keinen Private Key hat (Test 7)' {
        InModuleScope ExchangeOnlineGateway {
            $fakeCert = [PSCustomObject]@{
                Thumbprint    = 'AABB'
                HasPrivateKey = $false
                NotAfter      = (Get-Date).AddYears(1)
            }
            Mock Get-ExchangeOnlineCertificateInternal { $fakeCert }

            { Test-ExchangeOnlineCertificate -Thumbprint 'AABB' } |
            Should -Throw -ExpectedMessage '*private*Schlüssel*'
        }
    }

    # ─── Test 8: Abgelaufenes Zertifikat → klare Diagnose ──────────────────
    It 'liefert klare Diagnose wenn Zertifikat abgelaufen ist (Test 8)' {
        InModuleScope ExchangeOnlineGateway {
            $fakeCert = [PSCustomObject]@{
                Thumbprint    = 'AABB'
                HasPrivateKey = $true
                NotAfter      = (Get-Date).AddYears(-1)
            }
            Mock Get-ExchangeOnlineCertificateInternal { $fakeCert }
            Mock Get-EXODateInternal { Get-Date }

            { Test-ExchangeOnlineCertificate -Thumbprint 'AABB' } |
            Should -Throw -ExpectedMessage '*abgelaufen*'
        }
    }

    # ─── Test 13: Produktive Werte stehen nicht in appsettings.json ────────
    It 'appsettings.json enthält keine produktiven KSBL EXO-Werte (Test 13)' {
        $script:appSettings.ExchangeOnline.Enabled | Should -Be $false
        $script:appSettings.ExchangeOnline.AppId   | Should -Be ''
        $script:appSettings.ExchangeOnline.Organization | Should -Be ''
        $script:appSettings.ExchangeOnline.TenantDomain | Should -Be ''
        $script:appSettings.ExchangeOnline.CertificateThumbprint | Should -Be ''
    }

    # ─── Test 14: AppId, Organization, Thumbprint stehen in hybrid.json ────
    It 'environments.hybrid.json enthält produktive EXO-Werte AppId, Organization, CertificateThumbprint (Test 14)' {
        $script:hybridConfig.ExchangeOnline.Enabled | Should -Be $true

        $script:hybridConfig.ExchangeOnline.AppId | Should -Match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        $script:hybridConfig.ExchangeOnline.CertificateThumbprint | Should -Match '^[A-Fa-f0-9]{40}$'

        $orgOrTenant = @(
            $script:hybridConfig.ExchangeOnline.Organization,
            $script:hybridConfig.ExchangeOnline.TenantDomain
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        $orgOrTenant.Count | Should -BeGreaterThan 0
        $orgOrTenant -join ';' | Should -Match 'onmicrosoft\.com$'
    }
}
